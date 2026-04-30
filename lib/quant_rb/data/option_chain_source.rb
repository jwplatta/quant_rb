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
      - run shared validation and repair
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
        build_sample_index! unless @config.synthetic?
      end

      def chains_at(target_time, expiry_filter: nil)
        if @config.synthetic?
          synthetic_chains_at(target_time, expiry_filter:)
        else
          sampled_chains_at(target_time, expiry_filter:)
        end
      end

      def available_dates
        return (@start_date..@end_date).to_a if @config.synthetic?

        @sample_index.values.flat_map { |samples| samples.map(&:first).map(&:to_date) }.uniq.sort
      end

      private

      def synthetic_chains_at(target_time, expiry_filter:)
        expiry_dates = candidate_expiries(target_time, expiry_filter)
        expiry_dates.each_with_object({}) do |expiry, result|
          result[expiry] = synthetic_builder.build(target_time:, expiration_date: expiry, symbol: @config.option_root)
        rescue ArgumentError
          nil
        end
      end

      def sampled_chains_at(target_time, expiry_filter:)
        @sample_index.each_with_object({}) do |(expiry, samples), result|
          next if expiry < target_time.to_date
          next unless matches_expiry_filter?(expiry, expiry_filter)

          chain = locf_chain_for(samples, target_time)
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
            end_date: @end_date
          )
          iv_series_map = @config.iv_map.values.uniq.each_with_object({}) do |ticker, map|
            map[ticker] = @adapter.load_candle_series(
              provider: @config.provider,
              ticker: ticker,
              resolution: @config.resolution,
              start_date: @start_date,
              end_date: @end_date
            )
          end

          Synthetic::SyntheticChainBuilder.new(
            spx_series: underlying_series,
            vix_series: iv_series_map[@config.iv_proxy_for_dte(30)] || iv_series_map.values.first,
            vix9d_series: iv_series_map[@config.iv_proxy_for_dte(9)],
            vix1d_series: iv_series_map[@config.iv_proxy_for_dte(0)],
            underlying_symbol: @config.underlying,
            pricing_model: @config.pricing_model,
            strike_grid: @config.strike_grid,
            iv_map: @config.iv_map,
            validator: @validator
          )
        end
      end

      def build_sample_index!
        rows = @adapter.load_option_chain_rows(
          provider: @config.provider,
          ticker: @config.underlying,
          option_root: @config.option_root,
          resolution: @config.resolution,
          start_date: @start_date,
          end_date: @end_date
        )

        grouped = rows.group_by do |row|
          metadata = row.fetch("metadata")
          [metadata.fetch("expiration_date"), metadata.fetch("sampled_at")]
        end

        @sample_index = grouped.each_with_object(Hash.new { |h, k| h[k] = [] }) do |((expiry, sampled_at), snapshot_rows), index|
          chain = build_chain_from_rows(snapshot_rows, sampled_at: sampled_at, expiry: expiry)
          index[expiry] << [sampled_at, chain]
        end

        @sample_index.each_value { |samples| samples.sort_by!(&:first) }
      end

      def build_chain_from_rows(rows, sampled_at:, expiry:)
        options = rows.map { |row| build_option(row, sampled_at:) }.compact
        calls = options.select(&:call?).sort_by(&:strike)
        puts_ = options.select(&:put?).sort_by(&:strike)
        underlying_price = options.map(&:underlying_price).compact.first
        chain = QuantRb::DataObjects::OptionsChain.new(symbol: @config.option_root, underlying_price: underlying_price, call_opts: calls, put_opts: puts_)

        process_chain!(chain, expiry:)
      end

      def process_chain!(chain, expiry:)
        reconstruct_chain!(chain, expiry:) if @config.sampled_interpolated?

        @validator.repair(chain) if @config.validation == :repair
        enrich_chain!(chain) if @config.sampled_interpolated?
        chain
      end

      def reconstruct_chain!(chain, expiry:)
        all_by_side = [chain.call_opts, chain.put_opts]
        all_by_side.each do |options|
          next if options.empty?

          infer_missing_marks!(options)
          target_strikes = target_strikes_for(chain.underlying_price, options.map(&:strike))
          fill_missing_strikes!(options, target_strikes, expiry:, underlying_price: chain.underlying_price)
          interpolate_missing_marks!(options)
        end
      end

      def enrich_chain!(chain)
        chain.all_options.each do |option|
          next unless option.mark

          tau_years = [[option.days_to_expiration, 0].max, 1].max / 365.25
          sigma = Pricing::ImpliedVolatilitySolver.solve(
            market_price: option.mark,
            spot: option.underlying_price,
            strike: option.strike,
            tau_years: tau_years,
            rate: 0.0,
            contract_type: option.put_call,
            pricing_model: @config.pricing_model
          )
          option.volatility = sigma ? (sigma * 100.0).round(4) : option.volatility
          next unless sigma

          option.delta = compute_delta(option, tau_years, sigma)
          option.gamma = Pricing::BlackScholes.gamma(spot: option.underlying_price, strike: option.strike, tau_years: tau_years, sigma: sigma, rate: 0.0)
          option.theta = Pricing::BlackScholes.theta(spot: option.underlying_price, strike: option.strike, tau_years: tau_years, sigma: sigma, rate: 0.0, contract_type: option.put_call)
          option.vega = Pricing::BlackScholes.vega(spot: option.underlying_price, strike: option.strike, tau_years: tau_years, sigma: sigma, rate: 0.0)
          option.rho = Pricing::BlackScholes.rho(spot: option.underlying_price, strike: option.strike, tau_years: tau_years, sigma: sigma, rate: 0.0, contract_type: option.put_call)
        end
      end

      def compute_delta(option, tau_years, sigma)
        case @config.pricing_model
        when :binomial
          Pricing::CrrBinomial.delta(spot: option.underlying_price, strike: option.strike, tau_years: tau_years, sigma: sigma, rate: 0.0, contract_type: option.put_call)
        else
          Pricing::BlackScholes.delta(spot: option.underlying_price, strike: option.strike, tau_years: tau_years, sigma: sigma, rate: 0.0, contract_type: option.put_call)
        end
      end

      def infer_missing_marks!(options)
        options.each do |option|
          next if option.mark

          prices = [option.open, option.high, option.low, option.close].compact
          option.mark = prices.sum / prices.size if prices.any?
          next unless option.mark

          option.bid = option.mark if option.bid.nil?
          option.ask = option.mark if option.ask.nil?
        end
      end

      def target_strikes_for(spot, existing_strikes)
        step = @config.strike_grid[:step].to_f
        min = existing_strikes.min || (spot * 0.8)
        max = existing_strikes.max || (spot * 1.2)
        current = min
        strikes = []
        while current <= max
          strikes << current.round(2)
          current += step
        end
        strikes
      end

      def fill_missing_strikes!(options, target_strikes, expiry:, underlying_price:)
        existing = options.each_with_object({}) { |option, memo| memo[option.strike] = option }
        target_strikes.each do |strike|
          next if existing[strike]

          contract_type = options.first&.put_call || QuantRb::CALL
          options << QuantRb::DataObjects::Option.new(
            symbol: "#{@config.option_root}_#{expiry}_#{contract_type[0]}_#{strike}",
            underlying_symbol: @config.underlying,
            strike: strike,
            put_call: contract_type,
            underlying_price: underlying_price,
            expiration_date: expiry,
            days_to_expiration: [expiry - @start_date, 0].max,
            mark: nil,
            bid: nil,
            ask: nil
          )
        end
        options.sort_by!(&:strike)
      end

      def interpolate_missing_marks!(options)
        options.each_with_index do |option, index|
          next if option.mark

          left = options[0...index].reverse.find(&:mark)
          right = options[(index + 1)..].find(&:mark)
          option.mark =
            if left && right
              weight = (option.strike - left.strike).to_f / (right.strike - left.strike)
              left.mark + (weight * (right.mark - left.mark))
            elsif left
              left.mark
            elsif right
              right.mark
            end
          next unless option.mark

          option.bid ||= option.mark
          option.ask ||= option.mark
        end
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

      def locf_chain_for(samples, target_time)
        entry = samples.reverse.find { |sampled_at, _chain| sampled_at <= target_time }
        entry&.last
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
    end
  end
end
