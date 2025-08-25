module OptionsTrader
  module Indicators
    module Greeks
      # Black-Scholes utility methods
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
      end

      class Delta
        # Calculate option delta
        # @param spot_price [Float] Current price of underlying asset
        # @param strike_price [Float] Option strike price
        # @param time_to_expiry [Float] Time to expiration in years
        # @param risk_free_rate [Float] Risk-free interest rate (as decimal)
        # @param volatility [Float] Implied volatility (as decimal)
        # @param option_type [Symbol] :call or :put
        # @return [Float] Delta value
        def self.calculate(spot_price:, strike_price:, time_to_expiry:, risk_free_rate:, volatility:, option_type: :call)
          d1_val = BlackScholes.d1(spot_price, strike_price, time_to_expiry, risk_free_rate, volatility)

          case option_type
          when :call
            BlackScholes.norm_cdf(d1_val)
          when :put
            BlackScholes.norm_cdf(d1_val) - 1.0
          else
            raise ArgumentError, "option_type must be :call or :put"
          end
        end
      end

      class Gamma
        # Calculate option gamma
        # @param spot_price [Float] Current price of underlying asset
        # @param strike_price [Float] Option strike price
        # @param time_to_expiry [Float] Time to expiration in years
        # @param risk_free_rate [Float] Risk-free interest rate (as decimal)
        # @param volatility [Float] Implied volatility (as decimal)
        # @return [Float] Gamma value (same for calls and puts)
        def self.calculate(spot_price:, strike_price:, time_to_expiry:, risk_free_rate:, volatility:)
          d1_val = BlackScholes.d1(spot_price, strike_price, time_to_expiry, risk_free_rate, volatility)
          numerator = BlackScholes.norm_pdf(d1_val)
          denominator = spot_price * volatility * Math.sqrt(time_to_expiry)
          numerator / denominator
        end
      end

      class Vega
        # Calculate option vega
        # @param spot_price [Float] Current price of underlying asset
        # @param strike_price [Float] Option strike price
        # @param time_to_expiry [Float] Time to expiration in years
        # @param risk_free_rate [Float] Risk-free interest rate (as decimal)
        # @param volatility [Float] Implied volatility (as decimal)
        # @return [Float] Vega value (same for calls and puts)
        def self.calculate(spot_price:, strike_price:, time_to_expiry:, risk_free_rate:, volatility:)
          d1_val = BlackScholes.d1(spot_price, strike_price, time_to_expiry, risk_free_rate, volatility)
          spot_price * BlackScholes.norm_pdf(d1_val) * Math.sqrt(time_to_expiry)
        end
      end

      class Theta
        # Calculate option theta (time decay)
        # @param spot_price [Float] Current price of underlying asset
        # @param strike_price [Float] Option strike price
        # @param time_to_expiry [Float] Time to expiration in years
        # @param risk_free_rate [Float] Risk-free interest rate (as decimal)
        # @param volatility [Float] Implied volatility (as decimal)
        # @param option_type [Symbol] :call or :put
        # @return [Float] Theta value (typically negative)
        def self.calculate(spot_price:, strike_price:, time_to_expiry:, risk_free_rate:, volatility:, option_type: :call)
          d1_val = BlackScholes.d1(spot_price, strike_price, time_to_expiry, risk_free_rate, volatility)
          d2_val = BlackScholes.d2(spot_price, strike_price, time_to_expiry, risk_free_rate, volatility)

          first_term = -(spot_price * BlackScholes.norm_pdf(d1_val) * volatility) / (2.0 * Math.sqrt(time_to_expiry))

          case option_type
          when :call
            second_term = -risk_free_rate * strike_price *
                         Math.exp(-risk_free_rate * time_to_expiry) *
                         BlackScholes.norm_cdf(d2_val)
          when :put
            second_term = risk_free_rate * strike_price *
                         Math.exp(-risk_free_rate * time_to_expiry) *
                         BlackScholes.norm_cdf(-d2_val)
          else
            raise ArgumentError, "option_type must be :call or :put"
          end

          first_term + second_term
        end
      end

      class Rho
        # Calculate option rho (interest rate sensitivity)
        # @param spot_price [Float] Current price of underlying asset
        # @param strike_price [Float] Option strike price
        # @param time_to_expiry [Float] Time to expiration in years
        # @param risk_free_rate [Float] Risk-free interest rate (as decimal)
        # @param volatility [Float] Implied volatility (as decimal)
        # @param option_type [Symbol] :call or :put
        # @return [Float] Rho value
        def self.calculate(spot_price:, strike_price:, time_to_expiry:, risk_free_rate:, volatility:, option_type: :call)
          d2_val = BlackScholes.d2(spot_price, strike_price, time_to_expiry, risk_free_rate, volatility)

          case option_type
          when :call
            strike_price * time_to_expiry *
            Math.exp(-risk_free_rate * time_to_expiry) *
            BlackScholes.norm_cdf(d2_val)
          when :put
            -strike_price * time_to_expiry *
            Math.exp(-risk_free_rate * time_to_expiry) *
            BlackScholes.norm_cdf(-d2_val)
          else
            raise ArgumentError, "option_type must be :call or :put"
          end
        end
      end
    end
  end
end
