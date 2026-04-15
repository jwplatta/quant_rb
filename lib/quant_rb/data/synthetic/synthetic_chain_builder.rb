# frozen_string_literal: true

require "date"

module QuantRb
  module Data
    module Synthetic
      class SyntheticChainBuilder
        PUT_ANCHOR_DELTAS = [0.05, 0.10, 0.25].freeze
        CALL_ANCHOR_DELTAS = [0.45, 0.25, 0.20, 0.15, 0.10, 0.05, 0.02, 0.01].freeze
        SECONDS_PER_YEAR = 365.25 * 24 * 60 * 60

        def initialize(spx_series:, vix_series:, vix9d_series: nil, vix1d_series: nil, underlying_symbol: "SPX", risk_free_rate: 0.0)
          @spx_series   = spx_series
          @vix_series   = vix_series
          @vix9d_series = vix9d_series
          @vix1d_series = vix1d_series
          @underlying_symbol = underlying_symbol
          @risk_free_rate = risk_free_rate
        end

        def build(target_time:, expiration_date:, symbol: "SPXW")
          snapshot = build_snapshot(target_time, expiration_date)
          derived_state = compute_derived_state(target_time)
          atm_vol = compute_atm_vol(snapshot[:tau_years], derived_state)
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

          enforce_no_arbitrage!(quotes, snapshot[:spot])

          QuantRb::DataObjects::OptionsChain.new(
            symbol: symbol,
            underlying_price: snapshot[:spot],
            call_opts: quotes.select(&:call?),
            put_opts: quotes.select(&:put?)
          )
        end

        private

        def build_snapshot(target_time, expiration_date)
          spx_candle = fetch_required_candle(@spx_series, target_time, "SPX")
          vix_candle = fetch_required_candle(@vix_series, target_time, "VIX")
          vix9d_candle = fetch_required_candle(@vix9d_series, target_time, "VIX9D")
          vix1d_candle = @vix1d_series&.at(target_time)

          expiry_close = Time.utc(expiration_date.year, expiration_date.month, expiration_date.day, 20, 0, 0)
          tau_seconds = [expiry_close - target_time.getutc, 60.0].max

          {
            spot: spx_candle.close.to_f,
            vix: vix_candle.close.to_f,
            vix9d: vix9d_candle.close.to_f,
            vix1d: vix1d_candle&.close&.to_f,
            tau_years: tau_seconds / SECONDS_PER_YEAR
          }
        end

        def fetch_required_candle(series, target_time, label)
          candle = series&.at(target_time)
          return candle if candle

          raise ArgumentError, "SyntheticChainBuilder requires #{label} candle data at #{target_time.utc}"
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
          short_vol_proxy = fetch_required_candle(@vix9d_series, target_time, "VIX9D").close.to_f if short_vol_proxy.zero?
          medium_vol_proxy = fetch_required_candle(@vix_series, target_time, "VIX").close.to_f

          prior_close = prior_day_candles.last&.close || current_candle.open
          overnight_open = current_day_candles.first&.open || current_candle.open
          prior_day_range = percent_range(prior_day_candles)
          rolling_ranges = rolling_days.values.last(5).map { |day_candles| percent_range(day_candles) }.compact

          {
            short_vol_proxy: short_vol_proxy,
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

        def compute_atm_vol(tau_years, derived_state)
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
              price = black_scholes_price(
                spot: spot,
                strike: strike,
                tau_years: tau_years,
                sigma: sigma,
                rate: @risk_free_rate,
                contract_type: contract_type
              )
              delta = black_scholes_delta(
                spot: spot,
                strike: strike,
                tau_years: tau_years,
                sigma: sigma,
                rate: @risk_free_rate,
                contract_type: contract_type
              )

              build_option(
                symbol: symbol,
                contract_type: contract_type,
                strike: strike,
                expiration_date: expiration_date,
                target_time: target_time,
                underlying_price: spot,
                mark: price,
                delta: delta,
                volatility: vol_pct
              )
            end
          end
        end

        def strike_grid(spot, strike_step: 5.0, range_ratio: 0.20)
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

        def build_option(symbol:, contract_type:, strike:, expiration_date:, target_time:, underlying_price:, mark:, delta:, volatility:)
          spread = [[mark * 0.02, 0.05].max, 1.00].min
          bid = [mark - (spread / 2.0), 0.01].max.round(4)
          ask = (bid + spread).round(4)
          intrinsic =
            if contract_type == :call
              [underlying_price - strike, 0.0].max
            else
              [strike - underlying_price, 0.0].max
            end

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
            delta: delta.round(6),
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

        def enforce_no_arbitrage!(quotes, spot)
          calls = quotes.select(&:call?).sort_by(&:strike)
          puts_ = quotes.select(&:put?).sort_by(&:strike)

          calls.each_with_index do |quote, index|
            intrinsic = [spot - quote.strike, 0.0].max
            quote.mark = [quote.mark, intrinsic].max.round(4)
            quote.bid = [quote.bid, intrinsic].max.round(4)
            quote.ask = [quote.ask, quote.bid].max.round(4)
            next if index.zero?

            quote.mark = [quote.mark, calls[index - 1].mark].min.round(4)
            quote.bid = [quote.bid, quote.mark].min.round(4)
            quote.ask = [quote.ask, quote.mark].max.round(4)
          end

          puts_.each_with_index do |quote, index|
            intrinsic = [quote.strike - spot, 0.0].max
            quote.mark = [quote.mark, intrinsic].max.round(4)
            quote.bid = [quote.bid, intrinsic].max.round(4)
            quote.ask = [quote.ask, quote.bid].max.round(4)
            next if index.zero?

            quote.mark = [quote.mark, puts_[index - 1].mark].max.round(4)
            quote.bid = [quote.bid, quote.mark].min.round(4)
            quote.ask = [quote.ask, quote.mark].max.round(4)
          end
        end

        def black_scholes_price(spot:, strike:, tau_years:, sigma:, rate:, contract_type:)
          intrinsic =
            if contract_type == :call
              [spot - strike, 0.0].max
            else
              [strike - spot, 0.0].max
            end
          return intrinsic if tau_years <= 0.0 || sigma <= 0.0

          d1_value = d1(spot, strike, tau_years, sigma, rate)
          d2_value = d1_value - sigma * Math.sqrt(tau_years)
          discount = Math.exp(-rate * tau_years)

          if contract_type == :call
            (spot * normal_cdf(d1_value)) - (strike * discount * normal_cdf(d2_value))
          else
            (strike * discount * normal_cdf(-d2_value)) - (spot * normal_cdf(-d1_value))
          end
        end

        def black_scholes_delta(spot:, strike:, tau_years:, sigma:, rate:, contract_type:)
          return(contract_type == :call ? (spot > strike ? 1.0 : 0.0) : (spot < strike ? -1.0 : 0.0)) if tau_years <= 0.0 || sigma <= 0.0

          d1_value = d1(spot, strike, tau_years, sigma, rate)
          contract_type == :call ? normal_cdf(d1_value) : (normal_cdf(d1_value) - 1.0)
        end

        def d1(spot, strike, tau_years, sigma, rate)
          numerator = Math.log(spot / strike) + ((rate + 0.5 * sigma * sigma) * tau_years)
          denominator = sigma * Math.sqrt(tau_years)
          numerator / denominator
        end

        def normal_cdf(value)
          0.5 * (1.0 + Math.erf(value / Math.sqrt(2.0)))
        end

        def inverse_normal_cdf(probability)
          raise ArgumentError, "Probability must be between 0 and 1" unless probability.positive? && probability < 1.0

          low = -10.0
          high = 10.0

          100.times do
            mid = 0.5 * (low + high)
            if normal_cdf(mid) < probability
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
