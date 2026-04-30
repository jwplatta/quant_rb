# frozen_string_literal: true

require "date"

module QuantRb
  module Data
    module Synthetic
      <<~DOC
        Builds a synthetic options chain from an underlying candle series and one or more
        implied-volatility proxy series.

        Assumptions:
        - The underlying series and required volatility series are aligned to the backtest
          timestamps that will request synthetic chains.
        - Time to expiry is measured in years, while volatility proxies and pricing inputs are
          treated as annualized values.
        - `vix_series` acts as the default volatility source. `vix9d_series` and `vix1d_series`
          are optional short-dated refinements.
        - If an `iv_map` is provided, DTE bucket selection uses the configured proxy ticker and
          falls back toward VIX when a shorter-dated proxy is missing.

        Logic:
        - The builder estimates an ATM volatility level from the available proxy inputs.
        - It shapes a simple synthetic volatility smile around anchor deltas.
        - It generates a strike grid around spot using the configured range and step size.
        - It prices each strike with the selected pricing model and derives a full greek set.
        - It constructs synthetic bid/ask quotes from the modeled mark and runs the shared
          option-chain validator/repair pass before returning the chain.

        Shortcuts in this Stage 1 implementation:
        - The smile shape is heuristic rather than calibrated to a market-observed surface.
        - Bid/ask prices are derived from a simple spread heuristic, not from microstructure data.
        - The builder repairs the final chain for monotonicity/intrinsic-floor issues rather than
          solving a stricter arbitrage-free surface optimization problem.
      DOC
      class SyntheticChainBuilder
        PUT_ANCHOR_DELTAS = [0.05, 0.10, 0.25].freeze
        CALL_ANCHOR_DELTAS = [0.45, 0.25, 0.20, 0.15, 0.10, 0.05, 0.02, 0.01].freeze
        SECONDS_PER_YEAR = 365.25 * 24 * 60 * 60

        def initialize(spx_series:, vix_series:, vix9d_series: nil, vix1d_series: nil, underlying_symbol: "SPX", risk_free_rate: 0.0, pricing_model: :black_scholes, strike_grid: {}, iv_map: {}, validator: nil)
          @spx_series   = spx_series
          @vix_series   = vix_series
          @vix9d_series = vix9d_series
          @vix1d_series = vix1d_series
          @underlying_symbol = underlying_symbol
          @risk_free_rate = risk_free_rate
          @pricing_model = pricing_model.to_sym
          @strike_grid = { step: 5.0, range_ratio: 0.20 }.merge((strike_grid || {}).transform_keys(&:to_sym))
          @iv_map = normalize_iv_map(iv_map)
          @validator = validator || Validation::OptionChainValidator.new
        end

        def build(target_time:, expiration_date:, symbol: "SPXW")
          snapshot = build_snapshot(target_time, expiration_date)
          derived_state = compute_derived_state(target_time)
          atm_vol = compute_atm_vol(snapshot[:tau_years], derived_state, selected_vol_proxy: snapshot[:selected_vol_proxy])
          anchor_points = build_anchor_points(
            spot: snapshot[:spot],
            tau_years: snapshot[:tau_years],
            atm_vol_pct: atm_vol,
            derived_state: derived_state
          )

          quotes = build_quotes(
            symbol: symbol,
            expiration_date: expiration_date,
            target_time: target_time,
            spot: snapshot[:spot],
            tau_years: snapshot[:tau_years],
            anchor_points: anchor_points
          )

          chain = QuantRb::DataObjects::OptionsChain.new(
            symbol: symbol,
            underlying_price: snapshot[:spot],
            call_opts: quotes.select(&:call?),
            put_opts: quotes.select(&:put?)
          )
          @validator.repair(chain)
        end

        private

        def build_snapshot(target_time, expiration_date)
          validate_series_alignment!(target_time)
          spx_candle = fetch_required_candle(@spx_series, target_time, @underlying_symbol)
          vix_candle = fetch_required_candle(@vix_series, target_time, "VIX")
          vix9d_candle = @vix9d_series&.at(target_time)
          vix1d_candle = @vix1d_series&.at(target_time)

          expiry_close = Time.utc(expiration_date.year, expiration_date.month, expiration_date.day, 20, 0, 0)
          tau_seconds = [expiry_close - target_time.getutc, 60.0].max
          dte = (expiration_date - target_time.to_date).to_i

          {
            spot: spx_candle.close.to_f,
            vix: vix_candle.close.to_f,
            vix9d: vix9d_candle&.close&.to_f,
            vix1d: vix1d_candle&.close&.to_f,
            tau_years: tau_seconds / SECONDS_PER_YEAR,
            selected_vol_proxy: select_vol_proxy(dte:, vix: vix_candle.close, vix9d: vix9d_candle&.close, vix1d: vix1d_candle&.close)
          }
        end

        def fetch_required_candle(series, target_time, label)
          candle = series&.at(target_time)
          return candle if candle

          raise ArgumentError, "SyntheticChainBuilder requires #{label} candle data at #{target_time.utc}"
        end

        def validate_series_alignment!(target_time)
          [@spx_series, @vix_series].each do |series|
            next if exact_candle_at(series, target_time)

            raise ArgumentError, "SyntheticChainBuilder input series are not aligned at #{target_time.utc}"
          end
        end

        def exact_candle_at(series, target_time)
          candle = series&.at(target_time)
          candle && candle.datetime == target_time
        end

        def compute_derived_state(target_time)
          spx_candles = @spx_series.to_a
          current_candle = fetch_required_candle(@spx_series, target_time, @underlying_symbol)
          current_day = current_candle.datetime.to_date

          current_day_candles = spx_candles.select do |candle|
            candle.datetime.to_date == current_day && candle.datetime <= target_time
          end
          prior_day = current_day - 1
          prior_day_candles = spx_candles.select { |candle| candle.datetime.to_date == prior_day }
          rolling_days = grouped_daily_candles(spx_candles).select { |date, _| date < current_day }.to_a.last(5).to_h

          short_vol_proxy = @vix1d_series&.at(target_time)&.close.to_f
          short_vol_proxy = @vix9d_series&.at(target_time)&.close.to_f if short_vol_proxy.zero?
          medium_vol_proxy = fetch_required_candle(@vix_series, target_time, "VIX").close.to_f

          prior_close = prior_day_candles.last&.close || current_candle.open
          overnight_open = current_day_candles.first&.open || current_candle.open
          prior_day_range = percent_range(prior_day_candles)
          rolling_ranges = rolling_days.values.last(5).map { |day_candles| percent_range(day_candles) }.compact

          {
            short_vol_proxy: short_vol_proxy.zero? ? medium_vol_proxy : short_vol_proxy,
            medium_vol_proxy: medium_vol_proxy,
            term_slope_abs: short_vol_proxy - medium_vol_proxy,
            term_slope_ratio: medium_vol_proxy.zero? ? 1.0 : short_vol_proxy / medium_vol_proxy,
            prior_day_range_pct: prior_day_range || 0.0,
            rolling_range_pct: rolling_ranges.empty? ? (prior_day_range || 0.0) : rolling_ranges.sum / rolling_ranges.length,
            prior_return_pct: prior_close.to_f.zero? ? 0.0 : ((current_candle.close / prior_close) - 1.0) * 100.0,
            overnight_gap_pct: prior_close.to_f.zero? ? 0.0 : ((overnight_open / prior_close) - 1.0) * 100.0
          }
        end

        def grouped_daily_candles(candles)
          candles.group_by { |candle| candle.datetime.to_date }.sort.to_h
        end

        def percent_range(day_candles)
          return nil if day_candles.nil? || day_candles.empty?

          low = day_candles.map(&:low).min
          high = day_candles.map(&:high).max
          close = day_candles.last.close.to_f
          return 0.0 if close.zero?

          ((high - low) / close) * 100.0
        end

        def compute_atm_vol(tau_years, derived_state, selected_vol_proxy: nil)
          return selected_vol_proxy.clamp(8.0, 120.0) if selected_vol_proxy

          short = derived_state.fetch(:short_vol_proxy)
          medium = derived_state.fetch(:medium_vol_proxy)
          tau_trading_days = tau_years * 252.0
          short_weight = tau_trading_days <= 1.25 ? 0.85 : 0.65
          blended = (short * short_weight) + (medium * (1.0 - short_weight))
          blended.clamp(8.0, 120.0)
        end

        def build_anchor_points(spot:, tau_years:, atm_vol_pct:, derived_state:)
          atm_vol = atm_vol_pct / 100.0
          slope_abs = derived_state.fetch(:term_slope_abs)
          slope_ratio = derived_state.fetch(:term_slope_ratio)
          realized_pressure = derived_state.fetch(:prior_day_range_pct) - derived_state.fetch(:rolling_range_pct)
          downside_intensity = 0.035 + [(-slope_abs * 0.012), 0.0].max + [realized_pressure * 0.010, 0.0].max
          upside_intensity = 0.006 + [(slope_abs * 0.003), 0.0].max
          curvature = 0.008 + [(1.0 - slope_ratio) * 0.012, 0.0].max

          points = PUT_ANCHOR_DELTAS.map do |absolute_delta|
            strike = strike_for_target_delta(spot, absolute_delta, :put, atm_vol, tau_years)
            wing = (0.50 - absolute_delta) / 0.45
            vol = atm_vol_pct * (1.0 + downside_intensity * wing + curvature * (wing**2))
            { type: :put, abs_delta: absolute_delta, x: Math.log(strike / spot), strike: strike, vol: vol }
          end

          points << { type: :atm, abs_delta: 0.50, x: 0.0, strike: spot, vol: atm_vol_pct }

          CALL_ANCHOR_DELTAS.each do |absolute_delta|
            strike = strike_for_target_delta(spot, absolute_delta, :call, atm_vol, tau_years)
            wing = (0.50 - absolute_delta) / 0.45
            vol = atm_vol_pct * (1.0 + upside_intensity * wing + (curvature * 0.25) * (wing**2))
            vol *= 1.15 if absolute_delta < 0.05
            points << { type: :call, abs_delta: absolute_delta, x: Math.log(strike / spot), strike: strike, vol: vol }
          end

          points.sort_by { |point| point[:x] }
        end

        def strike_for_target_delta(spot, absolute_delta, contract_type, sigma, tau_years)
          sqrt_t = Math.sqrt(tau_years)
          d1 =
            if contract_type == :call
              inverse_normal_cdf(absolute_delta)
            else
              -inverse_normal_cdf(absolute_delta)
            end

          exponent = -(d1 * sigma * sqrt_t - 0.5 * sigma * sigma * tau_years)
          spot * Math.exp(exponent)
        end

        def build_quotes(symbol:, expiration_date:, target_time:, spot:, tau_years:, anchor_points:)
          strike_grid(spot).flat_map do |strike|
            %i[call put].map do |contract_type|
              vol_pct = interpolate_vol(anchor_points, spot, strike)
              sigma = vol_pct / 100.0
              price = option_price(spot:, strike:, tau_years:, sigma:, contract_type:)
              greeks = option_greeks(spot:, strike:, tau_years:, sigma:, contract_type:)

              build_option(
                symbol: symbol,
                contract_type: contract_type,
                strike: strike,
                expiration_date: expiration_date,
                target_time: target_time,
                underlying_price: spot,
                mark: price,
                greeks: greeks,
                volatility: vol_pct
              )
            end
          end
        end

        def strike_grid(spot)
          strike_step = @strike_grid.fetch(:step).to_f
          range_ratio = @strike_grid.fetch(:range_ratio).to_f
          min_strike = ((spot * (1.0 - range_ratio)) / strike_step).floor * strike_step
          max_strike = ((spot * (1.0 + range_ratio)) / strike_step).ceil * strike_step

          current = min_strike
          strikes = []
          while current <= max_strike
            strikes << current.round(2)
            current += strike_step
          end
          strikes
        end

        def build_option(symbol:, contract_type:, strike:, expiration_date:, target_time:, underlying_price:, mark:, greeks:, volatility:)
          spread = [[mark * 0.02, 0.05].max, 1.00].min
          bid = [mark - (spread / 2.0), 0.01].max.round(4)
          ask = (bid + spread).round(4)
          intrinsic = Pricing::BlackScholes.intrinsic_value(
            spot: underlying_price,
            strike: strike,
            contract_type: contract_type == :call ? QuantRb::CALL : QuantRb::PUT
          )

          QuantRb::DataObjects::Option.new(
            symbol: option_symbol(symbol, expiration_date, contract_type, strike),
            underlying_symbol: @underlying_symbol,
            strike: strike,
            put_call: contract_type == :call ? QuantRb::CALL : QuantRb::PUT,
            underlying_price: underlying_price,
            expiration_date: expiration_date,
            days_to_expiration: (expiration_date - target_time.to_date).to_i,
            mark: mark.round(4),
            bid: bid,
            ask: ask,
            delta: greeks.fetch(:delta).round(6),
            gamma: greeks.fetch(:gamma).round(6),
            theta: greeks.fetch(:theta).round(6),
            vega: greeks.fetch(:vega).round(6),
            rho: greeks.fetch(:rho).round(6),
            timestamp: target_time,
            intrinsic: intrinsic.round(4),
            volatility: volatility.round(4)
          )
        end

        def option_symbol(symbol, expiration_date, contract_type, strike)
          side = contract_type == :call ? "C" : "P"
          formatted_strike = strike.to_i == strike ? strike.to_i.to_s : format("%.2f", strike)
          "#{symbol}_#{expiration_date}_#{side}_#{formatted_strike}"
        end

        def interpolate_vol(anchor_points, spot, strike)
          x = Math.log(strike / spot)
          points = anchor_points.sort_by { |point| point[:x] }
          return points.first[:vol] if x <= points.first[:x]
          return points.last[:vol] if x >= points.last[:x]

          left, right = points.each_cons(2).find { |a, b| x >= a[:x] && x <= b[:x] }
          weight = (x - left[:x]) / (right[:x] - left[:x])
          vol = left[:vol] + weight * (right[:vol] - left[:vol])
          vol.clamp(5.0, 200.0)
        end

        def option_price(spot:, strike:, tau_years:, sigma:, contract_type:)
          put_call = contract_type == :call ? QuantRb::CALL : QuantRb::PUT
          case @pricing_model
          when :binomial
            Pricing::CrrBinomial.price(spot: spot, strike: strike, tau_years: tau_years, sigma: sigma, rate: @risk_free_rate, contract_type: put_call)
          else
            Pricing::BlackScholes.price(spot: spot, strike: strike, tau_years: tau_years, sigma: sigma, rate: @risk_free_rate, contract_type: put_call)
          end
        end

        def option_delta(spot:, strike:, tau_years:, sigma:, contract_type:)
          put_call = contract_type == :call ? QuantRb::CALL : QuantRb::PUT
          case @pricing_model
          when :binomial
            Pricing::CrrBinomial.delta(spot: spot, strike: strike, tau_years: tau_years, sigma: sigma, rate: @risk_free_rate, contract_type: put_call)
          else
            Pricing::BlackScholes.delta(spot: spot, strike: strike, tau_years: tau_years, sigma: sigma, rate: @risk_free_rate, contract_type: put_call)
          end
        end

        def option_greeks(spot:, strike:, tau_years:, sigma:, contract_type:)
          put_call = contract_type == :call ? QuantRb::CALL : QuantRb::PUT
          return binomial_greeks(spot:, strike:, tau_years:, sigma:, contract_type: put_call) if @pricing_model == :binomial

          {
            delta: Pricing::BlackScholes.delta(spot: spot, strike: strike, tau_years: tau_years, sigma: sigma, rate: @risk_free_rate, contract_type: put_call),
            gamma: Pricing::BlackScholes.gamma(spot: spot, strike: strike, tau_years: tau_years, sigma: sigma, rate: @risk_free_rate),
            theta: Pricing::BlackScholes.theta(spot: spot, strike: strike, tau_years: tau_years, sigma: sigma, rate: @risk_free_rate, contract_type: put_call),
            vega: Pricing::BlackScholes.vega(spot: spot, strike: strike, tau_years: tau_years, sigma: sigma, rate: @risk_free_rate),
            rho: Pricing::BlackScholes.rho(spot: spot, strike: strike, tau_years: tau_years, sigma: sigma, rate: @risk_free_rate, contract_type: put_call)
          }
        end

        def binomial_greeks(spot:, strike:, tau_years:, sigma:, contract_type:)
          {
            delta: Pricing::CrrBinomial.delta(spot: spot, strike: strike, tau_years: tau_years, sigma: sigma, rate: @risk_free_rate, contract_type: contract_type),
            gamma: Pricing::CrrBinomial.gamma(spot: spot, strike: strike, tau_years: tau_years, sigma: sigma, rate: @risk_free_rate, contract_type: contract_type),
            theta: Pricing::CrrBinomial.theta(spot: spot, strike: strike, tau_years: tau_years, sigma: sigma, rate: @risk_free_rate, contract_type: contract_type),
            vega: Pricing::CrrBinomial.vega(spot: spot, strike: strike, tau_years: tau_years, sigma: sigma, rate: @risk_free_rate, contract_type: contract_type),
            rho: Pricing::CrrBinomial.rho(spot: spot, strike: strike, tau_years: tau_years, sigma: sigma, rate: @risk_free_rate, contract_type: contract_type)
          }
        end

        def select_vol_proxy(dte:, vix:, vix9d:, vix1d:)
          ticker = @iv_map.find { |threshold, _symbol| dte <= threshold }&.last
          case ticker
          when nil then nil
          when /VIX1D/i then vix1d&.to_f || vix9d&.to_f || vix&.to_f
          when /VIX9D/i then vix9d&.to_f || vix&.to_f
          else
            vix&.to_f
          end
        end

        def normalize_iv_map(value)
          return {} if value.nil?

          value.each_with_object([]) do |(raw_key, ticker), entries|
            threshold =
              case raw_key.to_s.upcase
              when /\A(\d+)DTE\z/
                Regexp.last_match(1).to_i
              when "ODTE", "0DTE"
                0
              else
                raise ArgumentError, "Unsupported IV bucket #{raw_key.inspect}"
              end

            entries << [threshold, ticker]
          end.sort_by(&:first).to_h
        end

        def inverse_normal_cdf(probability)
          raise ArgumentError, "Probability must be between 0 and 1" unless probability.positive? && probability < 1.0

          low = -10.0
          high = 10.0

          100.times do
            mid = 0.5 * (low + high)
            if Pricing::BlackScholes.normal_cdf(mid) < probability
              low = mid
            else
              high = mid
            end
          end

          0.5 * (low + high)
        end
      end
    end
  end
end
