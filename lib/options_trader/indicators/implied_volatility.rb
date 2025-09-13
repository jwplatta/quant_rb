module OptionsTrader
  module Indicators
    class ImpliedVolatility
      # Calculate implied volatility using Brent's method with CRR pricing
      # @param market_price [Float] Observed option market price (bid-ask midpoint)
      # @param spot_price [Float] Current price of underlying asset
      # @param strike_price [Float] Option strike price
      # @param time_to_expiry [Float] Time to expiration in years
      # @param risk_free_rate [Float] Risk-free interest rate (as decimal)
      # @param option_type [String] "CALL" or "PUT"
      # @param dividend_yield [Float] Annualized dividend yield (default 0)
      # @param tolerance [Float] Convergence tolerance (default 1e-6)
      # @return [Float] Implied volatility or nil if no solution found
      def self.calculate(
        market_price:,
        spot_price:,
        strike_price:,
        time_to_expiry:,
        risk_free_rate:,
        option_type: OptionsTrader::CALL,
        dividend_yield: 0.0,
        tolerance: 1e-6
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

        # Set bounds for volatility search
        vol_low = 0.001   # 0.1%
        vol_high = 5.0    # 500%

        # Ensure opposite signs at bounds
        f_low = objective_function.call(vol_low)
        f_high = objective_function.call(vol_high)

        return nil if f_low * f_high > 0

        brent_method(objective_function, vol_low, vol_high, tolerance)
      end

      private

      # Brent's method for root finding
      # Combines characteristics of secant and bisection methods
      def self.brent_method(func, a, b, tolerance, max_iterations = 100)
        fa = func.call(a)
        fb = func.call(b)

        return nil if fa * fb > 0

        # Ensure |f(a)| >= |f(b)|
        if fa.abs < fb.abs
          a, b = b, a
          fa, fb = fb, fa
        end

        c = a
        fc = fa
        mflag = true

        (1..max_iterations).each do |_|
          # Check convergence
          return b if fb.abs < tolerance || (b - a).abs < tolerance

          if fa != fc && fb != fc
            # Inverse quadratic interpolation
            s = a * fb * fc / ((fa - fb) * (fa - fc)) +
                b * fa * fc / ((fb - fa) * (fb - fc)) +
                c * fa * fb / ((fc - fa) * (fc - fb))
          else
            # Secant method
            s = b - fb * (b - a) / (fb - fa)
          end

          # Check if we should use bisection instead
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

          # Ensure |f(a)| >= |f(b)|
          if fa.abs < fb.abs
            a, b = b, a
            fa, fb = fb, fa
          end
        end

        b # Return best approximation
      end
    end
  end
end
