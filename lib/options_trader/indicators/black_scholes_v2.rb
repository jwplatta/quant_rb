module OptionsTrader
  module Indicators
    module BlackScholesV2
      extend self

      # Standard normal CDF approximation
      def norm_cdf(x)
        return 0.0 if x < -10
        return 1.0 if x > 10

        # Abramowitz and Stegun approximation
        sign = x >= 0 ? 1 : -1
        x = x.abs

        # Constants
        a1 =  0.254829592
        a2 = -0.284496736
        a3 =  1.421413741
        a4 = -1.453152027
        a5 =  1.061405429
        p  =  0.3275911

        t = 1.0 / (1.0 + p * x)
        y = 1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * Math.exp(-x * x)

        0.5 * (1.0 + sign * y)
      end

      # Standard normal PDF
      def norm_pdf(x)
        Math.exp(-0.5 * x * x) / Math.sqrt(2 * Math::PI)
      end

      # Calculate d1 and d2
      def calculate_d_values(spot, strike, time_to_expiry, risk_free_rate, volatility, dividend_yield = 0.0)
        d1 = (Math.log(spot / strike) + (risk_free_rate - dividend_yield + 0.5 * volatility**2) * time_to_expiry) /
             (volatility * Math.sqrt(time_to_expiry))
        d2 = d1 - volatility * Math.sqrt(time_to_expiry)
        [d1, d2]
      end

      # Calculate option price
      def option_price(spot, strike, time_to_expiry, risk_free_rate, volatility, option_type, dividend_yield = 0.0)
        d1, d2 = calculate_d_values(spot, strike, time_to_expiry, risk_free_rate, volatility, dividend_yield)

        case option_type.upcase
        when 'CALL'
          spot * Math.exp(-dividend_yield * time_to_expiry) * norm_cdf(d1) -
          strike * Math.exp(-risk_free_rate * time_to_expiry) * norm_cdf(d2)
        when 'PUT'
          strike * Math.exp(-risk_free_rate * time_to_expiry) * norm_cdf(-d2) -
          spot * Math.exp(-dividend_yield * time_to_expiry) * norm_cdf(-d1)
        else
          raise ArgumentError, "option_type must be 'CALL' or 'PUT'"
        end
      end

      # Calculate all Greeks at once
      def calculate_greeks(spot, strike, time_to_expiry, risk_free_rate, volatility, option_type, dividend_yield = 0.0)
        return nil if time_to_expiry <= 0

        d1, d2 = calculate_d_values(spot, strike, time_to_expiry, risk_free_rate, volatility, dividend_yield)

        sqrt_t = Math.sqrt(time_to_expiry)
        exp_neg_rt = Math.exp(-risk_free_rate * time_to_expiry)
        exp_neg_qt = Math.exp(-dividend_yield * time_to_expiry)

        nd1 = norm_cdf(d1)
        nd2 = norm_cdf(d2)
        nprime_d1 = norm_pdf(d1)

        case option_type.upcase
        when 'CALL'
          # Price
          price = spot * exp_neg_qt * nd1 - strike * exp_neg_rt * nd2

          # Delta
          delta = exp_neg_qt * nd1

          # Gamma (same for calls and puts)
          gamma = (exp_neg_qt * nprime_d1) / (spot * volatility * sqrt_t)

          # Theta (annualized)
          theta = ((-spot * nprime_d1 * volatility * exp_neg_qt) / (2 * sqrt_t) -
                  risk_free_rate * strike * exp_neg_rt * nd2 +
                  dividend_yield * spot * exp_neg_qt * nd1) / 365.0

          # Vega (1% change)
          vega = (spot * exp_neg_qt * nprime_d1 * sqrt_t) / 100.0

          # Rho (1% change)
          rho = (strike * time_to_expiry * exp_neg_rt * nd2) / 100.0

        when 'PUT'
          # Price
          price = strike * exp_neg_rt * norm_cdf(-d2) - spot * exp_neg_qt * norm_cdf(-d1)

          # Delta
          delta = -exp_neg_qt * norm_cdf(-d1)

          # Gamma (same for calls and puts)
          gamma = (exp_neg_qt * nprime_d1) / (spot * volatility * sqrt_t)

          # Theta (annualized)
          theta = ((-spot * nprime_d1 * volatility * exp_neg_qt) / (2 * sqrt_t) +
                  risk_free_rate * strike * exp_neg_rt * norm_cdf(-d2) -
                  dividend_yield * spot * exp_neg_qt * norm_cdf(-d1)) / 365.0

          # Vega (1% change)
          vega = (spot * exp_neg_qt * nprime_d1 * sqrt_t) / 100.0

          # Rho (1% change)
          rho = (-strike * time_to_expiry * exp_neg_rt * norm_cdf(-d2)) / 100.0
        end

        {
          price: price,
          delta: delta,
          gamma: gamma,
          theta: theta,
          vega: vega,
          rho: rho,
          d1: d1,
          d2: d2
        }
      end

      # Implied volatility using Newton-Raphson
      def implied_volatility(market_price:, spot_price:, strike_price:, time_to_expiry:, risk_free_rate:, option_type:, dividend_yield: 0.0)

        return nil if market_price <= 0 || time_to_expiry <= 0

        # Initial guess
        vol = 0.25
        tolerance = 1e-8
        max_iterations = 100

        max_iterations.times do |t|
          greeks = calculate_greeks(spot_price, strike_price, time_to_expiry, risk_free_rate, vol, option_type, dividend_yield)

          price_diff = greeks[:price] - market_price
          if price_diff.abs < tolerance
            binding.pry
            return vol
          end

          # Newton-Raphson step: vol_new = vol_old - f(vol) / f'(vol)
          # f(vol) = theoretical_price - market_price
          # f'(vol) = vega (but need to convert from 1% to absolute)
          vega_absolute = greeks[:vega] * 100.0
          vol_new = vol - price_diff / vega_absolute

          # Keep volatility in reasonable bounds
          vol_new = [[vol_new, 0.001].max, 5.0].min

          # Check convergence
          if (vol_new - vol).abs < tolerance
            binding.pry
            return vol
          end

          vol = vol_new
        end

        nil # Failed to converge
      end
    end

  end
end