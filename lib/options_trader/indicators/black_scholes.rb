module OptionsTrader
  module Indicators
    module BlackScholes
      # Standard normal cumulative distribution function
      def self.norm_cdf(x)
        (1.0 + Math.erf(x / Math.sqrt(2.0))) / 2.0
      end

      # Standard normal probability density function
      def self.norm_pdf(x)
        Math.exp(-0.5 * x * x) / Math.sqrt(2.0 * Math::PI)
      end

      def self.d1(spot_price, strike_price, time_to_expiry, risk_free_rate, volatility)
        numerator = Math.log(spot_price.to_f / strike_price.to_f) +
                   (risk_free_rate + 0.5 * volatility * volatility) * time_to_expiry
        denominator = volatility * Math.sqrt(time_to_expiry)
        numerator / denominator
      end

      # Calculate d2 for Black-Scholes
      def self.d2(spot_price, strike_price, time_to_expiry, risk_free_rate, volatility)
        d1_val = d1(spot_price, strike_price, time_to_expiry, risk_free_rate, volatility)
        d1_val - volatility * Math.sqrt(time_to_expiry)
      end

      # Black-Scholes option pricing model
      # @param spot_price [Float] Current price of underlying asset (S0)
      # @param strike_price [Float] Option strike price (K)
      # @param time_to_expiry [Float] Time to expiration in years (T)
      # @param risk_free_rate [Float] Risk-free interest rate (r)
      # @param volatility [Float] Volatility (sigma)
      # @param option_type [String] "CALL" or "PUT"
      # @param dividend_yield [Float] Annualized dividend yield (default 0)
      # @return [Float] Option price
      def self.calculate(
        spot_price:,
        strike_price:,
        time_to_expiry:,
        risk_free_rate:,
        volatility:,
        option_type: OptionsTrader::CALL,
        dividend_yield: 0.0
      )
        d1_val = d1(spot_price, strike_price, time_to_expiry, risk_free_rate, volatility)
        d2_val = d2(spot_price, strike_price, time_to_expiry, risk_free_rate, volatility)

        case option_type
        when OptionsTrader::CALL
          # Call option: C = S*e^(-q*T)*N(d1) - K*e^(-r*T)*N(d2)
          spot_price * norm_cdf(d1_val) -
          strike_price * Math.exp(-risk_free_rate * time_to_expiry) * norm_cdf(d2_val)
        when OptionsTrader::PUT
          # Put option: P = K*e^(-r*T)*N(-d2) - S*e^(-q*T)*N(-d1)
          strike_price * Math.exp(-risk_free_rate * time_to_expiry) * norm_cdf(-d2_val) -
          spot_price * norm_cdf(-d1_val)
        else
          raise ArgumentError, "option_type must be CALL or PUT"
        end
      end
    end
  end
end
