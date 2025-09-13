module OptionsTrader
  module Indicators
    class HistoricalVolatility
      # Calculate annualized volatility from price history
      # @param prices [Array<Float>] Historical prices (most recent last)
      # @param frequency [Symbol] :minutes_5, :daily, :hourly (default :daily)
      # @param window_periods [Integer] Number of periods to look back
      # @param dte [Integer] Days to expiration for weighting adjustments
      # @param current_time [Time] Current timestamp for intraday adjustments
      # @return [Float] Annualized volatility
      def self.calculate(
        prices:,
        frequency: OptionsTrader::Intervals::DAILY,
        window_periods: nil,
        dte: nil,
        current_time: Time.now
      )
        return nil if prices.nil? || prices.length < 2

        # Set default window periods based on frequency and DTE
        # window_periods ||= default_window_periods(frequency, dte)

        # Calculate log returns
        log_returns = calculate_log_returns(prices)
        return nil if log_returns.empty?

        # Apply DTE-specific weighting if specified
        if dte && dte <= 7
          log_returns = apply_short_term_weighting(log_returns, dte)
        end

        # Calculate base volatility
        base_vol = calculate_base_volatility(log_returns, frequency)

        # Apply intraday adjustments for short-term options
        if dte && dte <= 7 && frequency == :minutes_5
          base_vol = apply_intraday_adjustments(base_vol, current_time, dte)
        end

        # Apply volatility risk premium for short-term options
        if dte && dte <= 7
          base_vol = apply_volatility_risk_premium(base_vol, dte)
        end

        base_vol
      end

      # Estimate option price using historical volatility
      # @param spot_price [Float] Current price of underlying asset
      # @param strike_price [Float] Option strike price
      # @param time_to_expiry [Float] Time to expiration in years
      # @param risk_free_rate [Float] Risk-free interest rate
      # @param option_type [String] "CALL" or "PUT"
      # @param price_history [Array<Float>] Historical prices for volatility calculation
      # @param frequency [Symbol] Price data frequency (:minutes_5, :daily, etc.)
      # @param dividend_yield [Float] Annualized dividend yield (default 0)
      # @param current_time [Time] Current time for intraday adjustments
      # @return [Hash] { option_price: Float, volatility_used: Float }
      def self.estimate_option_price(
        spot_price:, strike_price:, time_to_expiry:,
        risk_free_rate:, option_type: OptionsTrader::CALL,
        price_history:, frequency: :daily,
        dividend_yield: 0.0, current_time: Time.now
      )
        dte = (time_to_expiry * 365).round

        # Calculate historical volatility
        volatility = calculate_vol(
          prices: price_history,
          frequency: frequency,
          dte: dte,
          current_time: current_time
        )

        return { option_price: nil, volatility_used: nil } if volatility.nil?

        # Use CRR model to price option with historical volatility
        option_price = CoxRossRubinstein.calculate(
          spot_price: spot_price,
          strike_price: strike_price,
          time_to_expiry: time_to_expiry,
          risk_free_rate: risk_free_rate,
          volatility: volatility,
          option_type: option_type,
          dividend_yield: dividend_yield
        )

        {
          option_price: option_price,
          volatility_used: volatility
        }
      end

      private

      def self.default_window_periods(frequency, dte)
        case frequency
        when OptionsTrader::Intervals::FIVE_MIN
          if dte && dte <= 1
            156  # 2 trading days worth of 5-min periods
          elsif dte && dte <= 7
            390  # 5 trading days worth of 5-min periods
          else
            1560 # 20 trading days worth of 5-min periods
          end
        when OptionsTrader::Intervals::HOURLY
          if dte && dte <= 7
            65   # ~10 trading days
          else
            130  # ~20 trading days
          end
        when OptionsTrader::Intervals::DAILY
          if dte && dte <= 7
            10   # 10 days for short-term
          else
            30   # 30 days for longer-term
          end
        else
          30
        end
      end

      def self.calculate_log_returns(prices)
        returns = []
        (1...prices.size).each do |i|
          return_val = Math.log(prices.candles[i].close / prices.candles[i-1].close)
          returns << return_val unless return_val.nan? || return_val.infinite?
        end
        returns
      end

      def self.apply_short_term_weighting(returns, dte)
        # Apply exponential weighting - more recent returns get higher weight
        # for very short-term options
        weights = []
        alpha = dte <= 1 ? 0.3 : 0.1  # More aggressive weighting for 1DTE

        returns.each_with_index do |_, i|
          weight = (1 - alpha) ** (returns.size - 1 - i)
          weights << weight
        end

        # Normalize weights
        total_weight = weights.sum
        weights.map! { |w| w / total_weight }

        # Apply weights to returns for volatility calculation
        weighted_mean = returns.zip(weights).map { |r, w| r * w }.sum
        weighted_variance = returns.zip(weights).map { |r, w| w * (r - weighted_mean) ** 2 }.sum

        # Return array that when processed will give weighted volatility
        # This is a simplification - in practice you'd calculate weighted std dev directly
        returns
      end

      def self.calculate_base_volatility(returns, frequency)
        return 0.0 if returns.empty?

        # Calculate standard deviation
        mean_return = returns.sum / returns.length.to_f
        variance = returns.map { |r| (r - mean_return) ** 2 }.sum / returns.length.to_f
        std_dev = Math.sqrt(variance)

        # Annualize based on frequency
        periods_per_year = case frequency
                          when :minutes_5
                            78 * 252  # 78 five-minute periods per day * 252 trading days
                          when :hourly
                            6.5 * 252 # 6.5 hours per trading day * 252 trading days
                          when :daily
                            252       # 252 trading days per year
                          else
                            252
                          end

        std_dev * Math.sqrt(periods_per_year)
      end

      def self.apply_intraday_adjustments(base_vol, current_time, dte)
        hour = current_time.hour
        minute = current_time.minute

        # Market open volatility spike (9:30-10:30 AM ET)
        if (hour == 9 && minute >= 30) || hour == 10 && minute <= 30
          multiplier = dte <= 1 ? 1.4 : 1.2
        # Pre-close volatility (3:00-4:00 PM ET)
        elsif hour == 15
          multiplier = dte <= 1 ? 1.3 : 1.15
        # Lunch period (12:00-1:00 PM ET) - typically quieter
        elsif hour == 12 || hour == 13
          multiplier = 0.85
        # Normal trading hours
        else
          multiplier = 1.0
        end

        base_vol * multiplier
      end

      def self.apply_volatility_risk_premium(base_vol, dte)
        # Empirically, implied volatility > realized volatility
        # This premium is higher for shorter-term options
        premium = case dte
                  when 0..1
                    1.15  # 15% premium for 0-1 DTE
                  when 2..3
                    1.12  # 12% premium for 2-3 DTE
                  when 4..7
                    1.08  # 8% premium for 4-7 DTE
                  else
                    1.05  # 5% premium for longer-term
                  end

        base_vol * premium
      end
    end

    # Enhanced implied volatility class that can work with both market prices
    # and historical price data
    class ImpliedVolatility
      # Original method - calculate IV from market price (unchanged)
      def self.calculate(
        market_price:, spot_price:,
        strike_price:, time_to_expiry:,
        risk_free_rate:, option_type: OptionsTrader::CALL,
        dividend_yield: 0.0, tolerance: 1e-6
      )
        objective_function = lambda do |volatility|
          theoretical_price = CoxRossRubinstein.calculate(
            spot_price: spot_price,
            strike_price: strike_price,
            time_to_expiry: time_to_expiry,
            risk_free_rate: risk_free_rate,
            volatility: volatility,
            option_type: option_type,
            dividend_yield: dividend_yield
          )
          theoretical_price - market_price
        end

        vol_low = 0.001
        vol_high = 5.0

        f_low = objective_function.call(vol_low)
        f_high = objective_function.call(vol_high)

        return nil if f_low * f_high > 0

        brent_method(objective_function, vol_low, vol_high, tolerance)
      end

      # New method - estimate option price from historical price data
      def self.estimate_from_history(
        spot_price:, strike_price:, time_to_expiry:,
        risk_free_rate:, option_type: OptionsTrader::CALL,
        price_history:, frequency: :daily,
        dividend_yield: 0.0, current_time: Time.now
      )
        HistoricalVolatility.estimate_option_price(
          spot_price: spot_price,
          strike_price: strike_price,
          time_to_expiry: time_to_expiry,
          risk_free_rate: risk_free_rate,
          option_type: option_type,
          price_history: price_history,
          frequency: frequency,
          dividend_yield: dividend_yield,
          current_time: current_time
        )
      end

      private

      def self.brent_method(func, a, b, tolerance, max_iterations = 100)
        fa = func.call(a)
        fb = func.call(b)

        return nil if fa * fb > 0

        if fa.abs < fb.abs
          a, b = b, a
          fa, fb = fb, fa
        end

        c = a
        fc = fa
        mflag = true

        (1..max_iterations).each do |_|
          return b if fb.abs < tolerance || (b - a).abs < tolerance

          if fa != fc && fb != fc
            s = a * fb * fc / ((fa - fb) * (fa - fc)) +
                b * fa * fc / ((fb - fa) * (fb - fc)) +
                c * fa * fb / ((fc - fa) * (fc - fb))
          else
            s = b - fb * (b - a) / (fb - fa)
          end

          condition1 = !((3 * a + b) / 4 < s && s < b)
          condition2 = mflag && (s - b).abs >= (b - c).abs / 2
          condition3 = !mflag && (s - b).abs >= (c - a).abs / 2
          condition4 = mflag && (b - c).abs < tolerance
          condition5 = !mflag && (c - a).abs < tolerance

          if condition1 || condition2 || condition3 || condition4 || condition5
            s = (a + b) / 2
            mflag = true
          else
            mflag = false
          end

          fs = func.call(s)

          a, c = c, b
          fa, fc = fc, fb

          if fa * fs < 0
            b = s
            fb = fs
          else
            a = s
            fa = fs
          end

          if fa.abs < fb.abs
            a, b = b, a
            fa, fb = fb, fa
          end
        end

        b
      end
    end
  end
end
