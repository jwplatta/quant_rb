# frozen_string_literal: true

module QuantRb
  module Data
    <<~DOC
      Public option-chain source interface for backtests.

      In Stage 1 this class is intentionally load-bearing: it is the main orchestration layer
      behind `add_index_option(...)` after strategy subscription config has been normalized.

      Responsibilities:
      - dispatch between synthetic, sampled-interpolated, and sampled-validated chain modes
      - acquire raw option-chain rows through the Tickrake adapter
      - index sampled snapshots by expiry and sampled time, then serve them with LOCF semantics
      - normalize raw rows into `Option` and `OptionsChain` objects
      - run sampled reconstruction steps when interpolation mode is enabled
      - run shared validation and repair for synthetic and sampled-interpolated chains
      - preserve complete sampled chains as pass-through snapshots in sampled-validated mode
      - derive IV and greeks for reconstructed sampled chains
      - delegate synthetic surface generation to `SyntheticChainBuilder`

      Design note:
      - This is more than a pass-through adapter in Stage 1. It is the integration seam for the
        new pipeline, and may be split later into smaller loader/index/pipeline objects once the
        mode-specific behavior stabilizes.
    DOC
    class OptionChainSource
      def self.build(config:, start_date:, end_date:, adapter: nil, validator: nil)
        new(config:, start_date:, end_date:, adapter:, validator:)
      end

      def initialize(config:, start_date:, end_date:, adapter: nil, validator: nil)
        @config = config
        @start_date = start_date
        @end_date = end_date
        @adapter = adapter || Adapters::TickrakeAdapter.new
        @validator = validator || Validation::OptionChainValidator.new
        @cache = {}
        @sample_index = nil
        @sample_row_index = Hash.new { |h, k| h[k] = [] }
        @sample_row_enumerator = nil
        @sample_row_exhausted = false
        @sample_row_lookahead = nil
      end

      def chains_at(target_time, expiry_filter: nil)
        if @config.synthetic?
          synthetic_chains_at(target_time, expiry_filter:)
        else
          sampled_chains_at(target_time, expiry_filter:)
        end
      end

      def preload!
        return self if @config.synthetic?

        sampled_underlying_series
        self
      end

      def available_dates
        return (@start_date..@end_date).to_a if @config.synthetic?

        consume_all_sample_rows!
        @sample_row_index.values.flat_map { |samples| samples.map(&:first).map(&:to_date) }.uniq.sort
      end

      private

      def synthetic_chains_at(target_time, expiry_filter:)
        expiry_dates = candidate_expiries(target_time, expiry_filter)
        expiry_dates.each_with_object({}) do |expiry, result|
          result[expiry] = synthetic_builder.build(target_time:, expiration_date: expiry, symbol: @config.option_root)
        end
      end

      def sampled_chains_at(target_time, expiry_filter:)
        ensure_sample_row_stream!
        consume_sample_rows_through!(target_time)
        matching_expiries = @sample_row_index.keys.select do |expiry|
          QuantRb::OptionExpiration.active?(expiry, target_time, timezone_name: @config.market_timezone) &&
            matches_expiry_filter?(expiry, expiry_filter)
        end

        matching_expiries.each_with_object({}) do |expiry, result|
          chain = locf_chain_for_expiry(expiry, target_time)
          result[expiry] = chain if chain
        end
      end

      def synthetic_builder
        @synthetic_builder ||= begin
          underlying_series = @adapter.load_candle_series(
            provider: @config.provider,
            ticker: @config.underlying,
            resolution: @config.resolution,
            start_date: @start_date,
            end_date: @end_date,
            timezone: @config.market_timezone
          )
          iv_proxy_series = @adapter.load_candle_series(
            provider: @config.provider,
            ticker: @config.iv_proxy,
            resolution: @config.resolution,
            start_date: @start_date,
            end_date: @end_date,
            timezone: @config.market_timezone
          )

          Synthetic::SyntheticChainBuilder.new(
            underlying_series: underlying_series,
            iv_proxy_series: iv_proxy_series,
            underlying_symbol: @config.underlying,
            iv_proxy_symbol: @config.iv_proxy,
            pricing_model: @config.pricing_model,
            strike_grid: @config.strike_grid,
            validator: @validator
          )
        end
      end

      def ensure_sample_row_stream!
        return if @sample_row_enumerator || @sample_row_exhausted

        # TODO: Amortize sampled option-row loading over the life of the backtest by chunking the
        # stream into smaller date windows instead of opening one long-running enumerator across the
        # full backtest range at first use.
        QuantRb.logger.info("Loading sampled option data for backtest slices. This can take a bit before the first options-enabled bars run.")
        QuantRb.logger.info("Loading sampled option rows provider=#{@config.provider} underlying=#{@config.underlying} option_root=#{@config.option_root} resolution=#{@config.resolution}")
        @sample_row_enumerator = @adapter.load_option_chain_rows(
          provider: @config.provider,
          ticker: @config.underlying,
          option_root: @config.option_root,
          resolution: @config.resolution,
          start_date: @start_date,
          end_date: @end_date,
          timezone: @config.market_timezone
        )
        @sample_row_enumerator = @sample_row_enumerator.to_enum unless @sample_row_enumerator.respond_to?(:next)
        @sample_row_count = 0
      end

      def consume_sample_rows_through!(target_time)
        ensure_sample_row_stream!
        return if @sample_row_exhausted

        loop do
          row = next_sample_row
          break unless row

          sampled_at = sampled_at_for(row)
          if sampled_at > target_time
            @sample_row_lookahead = row
            break
          end

          store_sample_row(row)
        end
      end

      def consume_all_sample_rows!
        ensure_sample_row_stream!
        return if @sample_row_exhausted

        store_sample_row(@sample_row_lookahead) if @sample_row_lookahead
        @sample_row_lookahead = nil
        while (row = next_sample_row)
          store_sample_row(row)
        end
        @sample_row_exhausted = true
        log_sample_row_load_complete
      end

      def next_sample_row
        return nil if @sample_row_exhausted

        if @sample_row_lookahead
          row = @sample_row_lookahead
          @sample_row_lookahead = nil
          return row
        end

        @sample_row_enumerator.next
      rescue StopIteration
        @sample_row_exhausted = true
        log_sample_row_load_complete
        nil
      end

      def store_sample_row(row)
        return unless row

        metadata = row.fetch("metadata")
        expiry = metadata.fetch("expiration_date")
        sampled_at = sampled_at_for(row)
        samples = @sample_row_index[expiry]
        if samples.empty? || samples.last.first != sampled_at
          samples << [sampled_at, [row]]
        else
          samples.last.last << row
        end
        @sample_row_count += 1
      end

      def log_sample_row_load_complete
        return if @sample_row_load_logged

        QuantRb.logger.info("Loaded #{@sample_row_count || 0} sampled option rows provider=#{@config.provider} option_root=#{@config.option_root}")
        @sample_row_load_logged = true
      end

      def build_chain_from_rows(rows, sampled_at:, expiry:)
        options = rows.map { |row| build_option(row, sampled_at:) }.compact
        underlying_price = options.map(&:underlying_price).compact.first || sampled_underlying_price_at(sampled_at)
        ensure_underlying_price!(underlying_price, sampled_at)
        options.each { |option| hydrate_underlying_price!(option, underlying_price) }
        calls = options.select(&:call?).sort_by(&:strike)
        puts_ = options.select(&:put?).sort_by(&:strike)
        chain = QuantRb::DataObjects::OptionsChain.new(symbol: @config.option_root, underlying_price: underlying_price, call_opts: calls, put_opts: puts_)

        process_chain!(chain, expiry:, sampled_at:)
      end

      def process_chain!(chain, expiry:, sampled_at:)
        return chain if @config.sampled_validated?

        reconstruct_chain!(chain, expiry:, sampled_at:) if @config.sampled_interpolated?
        @validator.repair(chain) if @config.validation == :repair
        enrich_chain!(chain, sampled_at:) if @config.sampled_interpolated?
        chain
      end

      def reconstruct_chain!(chain, expiry:, sampled_at:)
        spot = chain.underlying_price
        [chain.call_opts, chain.put_opts].each do |options|
          next if options.empty?

          infer_missing_marks!(options)
        end

        tau_years = time_to_expiry_years(expiry, sampled_at)
        all_options = chain.all_options
        infer_observed_volatilities!(all_options, tau_years)
        target_strikes = target_strikes_for(spot, all_options.map(&:strike))
        fill_missing_strikes!(chain.call_opts, target_strikes, expiry:, sampled_at:, underlying_price: spot)
        fill_missing_strikes!(chain.put_opts, target_strikes, expiry:, sampled_at:, underlying_price: spot)
        all_options = chain.all_options
        unified_curve = build_unified_vol_curve(all_options, spot)
        apply_unified_vol_curve!(all_options, unified_curve, spot)
        reprice_options!(chain.call_opts, tau_years)
        reprice_options!(chain.put_opts, tau_years)
      end

      def enrich_chain!(chain, sampled_at:)
        tau_by_expiry = {}
        chain.all_options.each do |option|
          next unless option.mark

          hydrate_option_prices!(option)
          tau_years = (tau_by_expiry[option.expiration_date] ||= time_to_expiry_years(option.expiration_date, sampled_at))
          sigma = option.volatility ? option.volatility.to_f / 100.0 : inferred_sigma_for(option, tau_years)
          option.volatility = sigma ? (sigma * 100.0).round(4) : option.volatility
          next unless sigma

          greeks = compute_greeks(option, tau_years, sigma)
          option.delta = greeks.fetch(:delta)
          option.gamma = greeks.fetch(:gamma)
          option.theta = greeks.fetch(:theta)
          option.vega = greeks.fetch(:vega)
          option.rho = greeks.fetch(:rho)
        end
      end

      def inferred_sigma_for(option, tau_years)
        Pricing::ImpliedVolatilitySolver.solve(
          market_price: option.mark,
          spot: option.underlying_price,
          strike: option.strike,
          tau_years: tau_years,
          rate: 0.0,
          contract_type: option.put_call,
          pricing_model: @config.pricing_model
        )
      end

      def compute_delta(option, tau_years, sigma)
        case @config.pricing_model
        when :binomial
          Pricing::CrrBinomial.delta(spot: option.underlying_price, strike: option.strike, tau_years: tau_years, sigma: sigma, rate: 0.0, contract_type: option.put_call)
        else
          Pricing::BlackScholes.delta(spot: option.underlying_price, strike: option.strike, tau_years: tau_years, sigma: sigma, rate: 0.0, contract_type: option.put_call)
        end
      end

      def compute_greeks(option, tau_years, sigma)
        if @config.pricing_model == :binomial
          {
            delta: Pricing::CrrBinomial.delta(spot: option.underlying_price, strike: option.strike, tau_years: tau_years, sigma: sigma, rate: 0.0, contract_type: option.put_call),
            gamma: Pricing::CrrBinomial.gamma(spot: option.underlying_price, strike: option.strike, tau_years: tau_years, sigma: sigma, rate: 0.0, contract_type: option.put_call),
            theta: Pricing::CrrBinomial.theta(spot: option.underlying_price, strike: option.strike, tau_years: tau_years, sigma: sigma, rate: 0.0, contract_type: option.put_call),
            vega: Pricing::CrrBinomial.vega(spot: option.underlying_price, strike: option.strike, tau_years: tau_years, sigma: sigma, rate: 0.0, contract_type: option.put_call),
            rho: Pricing::CrrBinomial.rho(spot: option.underlying_price, strike: option.strike, tau_years: tau_years, sigma: sigma, rate: 0.0, contract_type: option.put_call)
          }
        else
          {
            delta: Pricing::BlackScholes.delta(spot: option.underlying_price, strike: option.strike, tau_years: tau_years, sigma: sigma, rate: 0.0, contract_type: option.put_call),
            gamma: Pricing::BlackScholes.gamma(spot: option.underlying_price, strike: option.strike, tau_years: tau_years, sigma: sigma, rate: 0.0),
            theta: Pricing::BlackScholes.theta(spot: option.underlying_price, strike: option.strike, tau_years: tau_years, sigma: sigma, rate: 0.0, contract_type: option.put_call),
            vega: Pricing::BlackScholes.vega(spot: option.underlying_price, strike: option.strike, tau_years: tau_years, sigma: sigma, rate: 0.0),
            rho: Pricing::BlackScholes.rho(spot: option.underlying_price, strike: option.strike, tau_years: tau_years, sigma: sigma, rate: 0.0, contract_type: option.put_call)
          }
        end
      end

      def infer_missing_marks!(options)
        options.each do |option|
          estimate_quote_from_observed_prices!(option)
        end
      end

      def infer_observed_volatilities!(options, tau_years)
        options.each do |option|
          next unless option.mark

          sigma = inferred_sigma_for(option, tau_years)
          option.volatility = (sigma * 100.0).round(4) if sigma
        end
      end

      def build_unified_vol_curve(options, spot)
        observed_points = preferred_vol_anchors(options, spot)
        observed_points = fallback_vol_anchors(options, spot) if observed_points.empty?

        grouped = observed_points.group_by(&:first).transform_values do |points|
          points.sum { |_x, vol| vol } / points.size.to_f
        end

        points = grouped.sort_by(&:first)
        { points: points, slopes: monotone_cubic_slopes(points) }
      end

      def preferred_vol_anchors(options, spot)
        otm_points = options.filter_map do |option|
          next unless option.volatility
          next unless spot.to_f.positive? && option.strike.to_f.positive?
          next unless otm_anchor_option?(option, spot)

          [log_moneyness(option.strike, spot), option.volatility.to_f]
        end

        return otm_points if otm_points.empty?

        augmented_points = otm_points.dup
        atm_option = nearest_atm_option(options, spot)
        if atm_option&.volatility
          augmented_points << [log_moneyness(atm_option.strike, spot), atm_option.volatility.to_f]
        end

        ensure_side_coverage!(augmented_points, options, spot, negative_side: true)
        ensure_side_coverage!(augmented_points, options, spot, negative_side: false)
        augmented_points
      end

      def fallback_vol_anchors(options, spot)
        options.filter_map do |option|
          next unless option.volatility
          next unless spot.to_f.positive? && option.strike.to_f.positive?

          [log_moneyness(option.strike, spot), option.volatility.to_f]
        end
      end

      def otm_anchor_option?(option, spot)
        (option.put? && option.strike.to_f <= spot.to_f) || (option.call? && option.strike.to_f >= spot.to_f)
      end

      def nearest_atm_option(options, spot)
        nearest = nil
        options.each do |option|
          next unless option.volatility && option.strike.to_f.positive?

          if nearest.nil? || (option.strike.to_f - spot.to_f).abs < (nearest.strike.to_f - spot.to_f).abs
            nearest = option
          end
        end
        nearest
      end

      def ensure_side_coverage!(points, options, spot, negative_side:)
        has_side = points.any? { |x, _vol| negative_side ? x <= 0.0 : x >= 0.0 }
        return if has_side

        candidate = nil
        options.each do |option|
          next unless option.volatility && option.strike.to_f.positive?
          next unless negative_side ? option.strike.to_f <= spot.to_f : option.strike.to_f >= spot.to_f

          if candidate.nil? || (option.strike.to_f - spot.to_f).abs < (candidate.strike.to_f - spot.to_f).abs
            candidate = option
          end
        end
        return unless candidate

        points << [log_moneyness(candidate.strike, spot), candidate.volatility.to_f]
      end

      def apply_unified_vol_curve!(options, curve, spot)
        return if curve[:points].empty?

        options.each do |option|
          x = log_moneyness(option.strike, spot)
          option.volatility = interpolate_curve_value(curve, x)&.round(4)
        end
      end

      def estimate_quote_from_observed_prices!(option)
        if option.bid && option.ask
          option.mark ||= option.mid
          return
        end

        midpoint = estimated_mark_for(option)
        return unless midpoint

        option.mark = midpoint
        spread = estimated_spread_for(option, midpoint)
        half_spread = spread / 2.0

        option.bid ||= [midpoint - half_spread, 0.0].max.round(4)
        option.ask ||= [midpoint + half_spread, option.bid].max.round(4)
      end

      def estimated_mark_for(option)
        return option.mid if option.bid && option.ask
        return option.bid if option.bid
        return option.ask if option.ask

        prices = [option.open, option.high, option.low, option.close].compact
        return weighted_ohlc_midpoint(prices, option) if prices.any?

        nil
      end

      def weighted_ohlc_midpoint(prices, option)
        return prices.sum / prices.size unless [option.open, option.high, option.low, option.close].all?

        ((option.open + option.high + option.low + (2.0 * option.close)) / 5.0).round(4)
      end

      def estimated_spread_for(option, midpoint)
        observed = [option.open, option.high, option.low, option.close].compact
        range_based = if option.high && option.low
          (option.high - option.low).abs * 0.35
        else
          0.0
        end
        variance_based = if observed.size >= 2
          mean = observed.sum / observed.size.to_f
          variance = observed.sum { |value| (value - mean)**2 } / observed.size.to_f
          Math.sqrt(variance)
        else
          0.0
        end

        spread = [range_based, variance_based, 0.05].max
        [spread.round(4), [midpoint.abs * 0.75, 5.0].min].min
      end

      def target_strikes_for(spot, existing_strikes)
        step = @config.strike_grid[:step].to_f
        range_ratio = @config.strike_grid[:range_ratio].to_f
        range_ratio = 0.20 if range_ratio <= 0.0
        downside_ratio = range_ratio * 1.5
        upside_ratio = range_ratio
        configured_min = [spot * (1.0 - downside_ratio), step].max
        configured_max = spot * (1.0 + upside_ratio)
        observed_min = existing_strikes.compact.select(&:positive?).min
        min = [observed_min || configured_min, configured_min].min
        max = [existing_strikes.max || configured_max, configured_max].max
        min = (min / step).floor * step
        max = (max / step).ceil * step
        min = step if min <= 0.0
        current = min
        strikes = []
        while current <= max
          strikes << current.round(2)
          current += step
        end
        strikes
      end

      def fill_missing_strikes!(options, target_strikes, expiry:, sampled_at:, underlying_price:)
        existing = options.each_with_object({}) { |option, memo| memo[option.strike] = option }
        target_strikes.each do |strike|
          next if existing[strike]

          contract_type = options.first&.put_call || QuantRb::CALL
          neighbors = neighboring_options(existing.values, strike)
          options << QuantRb::DataObjects::Option.new(
            symbol: generated_option_symbol(strike:, expiry:, contract_type:, neighbors:),
            underlying_symbol: @config.underlying,
            strike: strike,
            put_call: contract_type,
            underlying_price: underlying_price,
            expiration_date: expiry,
            days_to_expiration: [expiry - sampled_at.to_date, 0].max,
            timestamp: sampled_at,
            mark: nil,
            bid: nil,
            ask: nil
          )
        end
        options.sort_by!(&:strike)
      end

      def sampled_underlying_series
        @sampled_underlying_series ||= @adapter.load_candle_series(
          provider: sampled_underlying_provider,
          ticker: @config.underlying,
          resolution: @config.resolution,
          start_date: @start_date,
          end_date: @end_date,
          timezone: @config.market_timezone
        )
      end

      def sampled_underlying_price_at(sampled_at)
        sampled_underlying_series.at(sampled_at)&.close&.to_f
      end

      def sampled_underlying_provider
        @config.raw_options[:underlying_provider] || @config.provider
      end

      def ensure_underlying_price!(underlying_price, sampled_at)
        return unless underlying_price.nil?

        raise ArgumentError,
              "No underlying price for #{@config.underlying} at or before #{sampled_at.utc} " \
              "using provider #{sampled_underlying_provider.inspect} and resolution #{@config.resolution.inspect}"
      end

      def hydrate_underlying_price!(option, underlying_price)
        return if option.underlying_price || underlying_price.nil?

        option.instance_variable_set(:@underlying_price, underlying_price)
      end

      def reprice_options!(options, tau_years)
        options.each_with_index do |option, index|
          next unless option.volatility

          sigma = option.volatility.to_f / 100.0
          option.mark = theoretical_price_for(option, tau_years, sigma).round(4)
          left = nearest_left_quoted_option(options, index)
          right = nearest_right_quoted_option(options, index)
          spread = repriced_spread_for(option, left, right)
          half_spread = spread / 2.0
          option.bid = [option.mark - half_spread, 0.0].max.round(4)
          option.ask = [option.mark + half_spread, option.bid].max.round(4)
          hydrate_option_prices!(option)
        end
      end

      def nearest_left_quoted_option(options, index)
        pointer = index - 1
        while pointer >= 0
          option = options[pointer]
          return option if option.bid && option.ask

          pointer -= 1
        end
        nil
      end

      def nearest_right_quoted_option(options, index)
        pointer = index + 1
        while pointer < options.length
          option = options[pointer]
          return option if option.bid && option.ask

          pointer += 1
        end
        nil
      end

      def hydrate_option_prices!(option)
        ensure_underlying_price!(option.underlying_price, option.timestamp || Time.utc(option.expiration_date.year, option.expiration_date.month, option.expiration_date.day))
        option.intrinsic = Pricing::BlackScholes.intrinsic_value(
          spot: option.underlying_price,
          strike: option.strike,
          contract_type: option.put_call
        )
        option.extrinsic = [option.mark.to_f - option.intrinsic.to_f, 0.0].max if option.mark
        if option.mark && (option.bid.nil? || option.ask.nil?)
          spread = [option.mark.abs * 0.02, 0.05].max.round(4)
          half_spread = spread / 2.0
          option.bid ||= [option.mark - half_spread, 0.0].max.round(4)
          option.ask ||= [option.mark + half_spread, option.bid].max.round(4)
        end
      end

      def neighboring_options(options, strike)
        sorted = options.sort_by(&:strike)
        left = sorted.select { |option| option.strike < strike }.last
        right = sorted.find { |option| option.strike > strike }
        [left, right].compact
      end

      def repriced_spread_for(option, left, right)
        observed_spread = estimated_spread_for(option, option.mark)
        return observed_spread if sampled_quote_observation?(option)

        spreads = [left, right].compact.filter_map do |neighbor|
          next if neighbor.bid.nil? || neighbor.ask.nil?

          (neighbor.ask - neighbor.bid).abs
        end

        if spreads.empty?
          observed_spread
        else
          [[spreads.sum / spreads.size.to_f, 0.05].max, [option.mark.to_f.abs * 0.75, 5.0].min].min.round(4)
        end
      end

      def sampled_quote_observation?(option)
        option.bid || option.ask || option.open || option.high || option.low || option.close
      end

      def theoretical_price_for(option, tau_years, sigma)
        case @config.pricing_model
        when :binomial
          Pricing::CrrBinomial.price(
            spot: option.underlying_price,
            strike: option.strike,
            tau_years: tau_years,
            sigma: sigma,
            rate: 0.0,
            contract_type: option.put_call
          )
        else
          Pricing::BlackScholes.price(
            spot: option.underlying_price,
            strike: option.strike,
            tau_years: tau_years,
            sigma: sigma,
            rate: 0.0,
            contract_type: option.put_call
          )
        end
      end

      def log_moneyness(strike, spot)
        raise ArgumentError, "Cannot compute log moneyness with non-positive strike=#{strike.inspect} spot=#{spot.inspect}" if strike.to_f <= 0.0 || spot.to_f <= 0.0

        Math.log(strike.to_f / spot.to_f)
      end

      def interpolate_curve_value(curve, x_value)
        points = curve.fetch(:points)
        slopes = curve.fetch(:slopes)
        return points.first.last if points.length == 1

        left = nil
        right = nil
        left_index = nil
        right_index = nil
        points.each_with_index do |(x, value), index|
          left = [x, value] if x <= x_value
          left_index = index if x <= x_value
          if x >= x_value
            right = [x, value]
            right_index = index
            break
          end
        end

        return left.last if left && right.nil?
        return right.last if right && left.nil?
        return left.last if left.first == right.first

        hermite_interpolate(
          left_x: left.first,
          left_y: left.last,
          left_slope: slopes.fetch(left_index),
          right_x: right.first,
          right_y: right.last,
          right_slope: slopes.fetch(right_index),
          x_value: x_value
        )
      end

      def monotone_cubic_slopes(points)
        return [0.0] if points.length == 1

        xs = points.map(&:first)
        ys = points.map(&:last)
        deltas = []
        widths = []

        (0...points.length - 1).each do |index|
          width = xs[index + 1] - xs[index]
          widths << width
          deltas << ((ys[index + 1] - ys[index]) / width.to_f)
        end

        slopes = Array.new(points.length, 0.0)
        slopes[0] = deltas.first
        slopes[-1] = deltas.last

        (1...points.length - 1).each do |index|
          if deltas[index - 1].zero? || deltas[index].zero? || (deltas[index - 1] <=> 0) != (deltas[index] <=> 0)
            slopes[index] = 0.0
            next
          end

          weight_left = (2.0 * widths[index]) + widths[index - 1]
          weight_right = widths[index] + (2.0 * widths[index - 1])
          slopes[index] = (weight_left + weight_right) / ((weight_left / deltas[index - 1]) + (weight_right / deltas[index]))
        end

        slopes
      end

      def hermite_interpolate(left_x:, left_y:, left_slope:, right_x:, right_y:, right_slope:, x_value:)
        interval = right_x - left_x
        t = (x_value - left_x).to_f / interval.to_f
        t2 = t * t
        t3 = t2 * t
        h00 = (2.0 * t3) - (3.0 * t2) + 1.0
        h10 = t3 - (2.0 * t2) + t
        h01 = (-2.0 * t3) + (3.0 * t2)
        h11 = t3 - t2

        (h00 * left_y) + (h10 * interval * left_slope) + (h01 * right_y) + (h11 * interval * right_slope)
      end

      def time_to_expiry_years(expiration_date, sampled_at)
        expiry_utc = QuantRb::OptionExpiration.expiration_time_utc(expiration_date, timezone_name: @config.market_timezone)
        [[expiry_utc - sampled_at.getutc, 60.0].max / Synthetic::SyntheticChainBuilder::SECONDS_PER_YEAR, (1.0 / 365.25)].max
      end

      def build_option(row, sampled_at:)
        expiration = row["expiration_date"] || row.dig("metadata", "expiration_date")
        put_call = (row["contract_type"] || row["put_call"]).to_s.upcase
        put_call = QuantRb::CALL if put_call == "C"
        put_call = QuantRb::PUT if put_call == "P"
        return nil unless [QuantRb::CALL, QuantRb::PUT].include?(put_call)

        QuantRb::DataObjects::Option.new(
          symbol: row["symbol"] || row["ticker"] || option_symbol_from_row(row, sampled_at),
          underlying_symbol: row["underlying_symbol"] || @config.underlying,
          strike: row["strike"],
          put_call: put_call,
          underlying_price: row["underlying_price"],
          expiration_date: expiration,
          days_to_expiration: (expiration - sampled_at.to_date).to_i,
          mark: row["mark"],
          bid: row["bid"],
          ask: row["ask"],
          open_interest: row["open_interest"] || 0,
          total_volume: row["total_volume"] || 0,
          delta: row["delta"],
          gamma: row["gamma"],
          theta: row["theta"],
          vega: row["vega"],
          rho: row["rho"],
          volatility: row["volatility"],
          timestamp: sampled_at,
          intrinsic: row["intrinsic_value"],
          extrinsic: row["extrinsic_value"],
          open: row["open"],
          high: row["high"],
          low: row["low"],
          close: row["close"]
        )
      end

      def option_symbol_from_row(row, sampled_at)
        expiry = row["expiration_date"] || row.dig("metadata", "expiration_date")
        "#{@config.option_root}_#{expiry}_#{row["put_call"] || row["contract_type"]}_#{row["strike"]}_#{sampled_at.to_i}"
      end

      def generated_option_symbol(strike:, expiry:, contract_type:, neighbors:)
        template = neighbors.find { |option| option.symbol&.match?(/\d{6}[CP]\d{8}\z/) }&.symbol
        return occ_like_option_symbol(strike:, expiry:, contract_type:, template:) if template

        occ_like_option_symbol(strike:, expiry:, contract_type:)
      end

      def occ_like_option_symbol(strike:, expiry:, contract_type:, template: nil)
        prefix =
          if template && (match = template.match(/\A(?<prefix>.*?)(?<date>\d{6})(?<type>[CP])\d{8}\z/))
            match[:prefix]
          else
            @config.option_root.ljust(6)
          end

        "#{prefix}#{expiry.strftime("%y%m%d")}#{contract_type == QuantRb::CALL ? 'C' : 'P'}#{format("%08d", (strike.to_f * 1000).round)}"
      end

      def locf_chain_for(samples, target_time)
        entry = samples.reverse.find { |sampled_at, _chain| sampled_at <= target_time }
        entry&.last
      end

      def locf_chain_for_expiry(expiry, target_time)
        @sample_index ||= {}
        expiry_cache = (@sample_index[expiry] ||= {})
        raw_samples = @sample_row_index.fetch(expiry, [])
        entry = raw_samples.reverse.find { |sampled_at, _snapshot_rows| sampled_at <= target_time }
        return nil unless entry

        sampled_at, snapshot_rows = entry
        return expiry_cache[sampled_at] if expiry_cache.key?(sampled_at)

        expiry_cache[sampled_at] = build_chain_from_rows(snapshot_rows, sampled_at: sampled_at, expiry: expiry)
      end

      def candidate_expiries(target_time, expiry_filter)
        dates = []
        date = target_time.to_date
        while dates.length < 30
          dates << date unless date.saturday? || date.sunday?
          date += 1
        end
        dates.select { |expiry| matches_expiry_filter?(expiry, expiry_filter) }
      end

      def matches_expiry_filter?(expiry, expiry_filter)
        return true if expiry_filter.nil?
        return expiry_filter.call(expiry) if expiry_filter.respond_to?(:call)
        return expiry_filter.cover?(expiry) if expiry_filter.respond_to?(:cover?)
        return expiry_filter.include?(expiry) if expiry_filter.respond_to?(:include?)

        expiry == expiry_filter
      end

      def sampled_at_for(row)
        row["sampled_at_tz"] ||
          row["sampled_at"] ||
          row.dig("metadata", "sampled_at_tz") ||
          row.dig("metadata", "sampled_at") ||
          raise(KeyError, "Sampled option row is missing sampled_at_tz/sample_time metadata")
      end

    end
  end
end
