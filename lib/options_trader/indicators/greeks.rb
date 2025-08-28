require_relative 'black_scholes'
require_relative 'cox_ross_rubinstein'

module OptionsTrader
  module Indicators
    module Greeks
      class Delta
        # Calculate option delta using Black-Scholes
        # @param spot_price [Float] Current price of underlying asset
        # @param strike_price [Float] Option strike price
        # @param time_to_expiry [Float] Time to expiration in years
        # @param risk_free_rate [Float] Risk-free interest rate (as decimal)
        # @param volatility [Float] Implied volatility (as decimal)
        # @param option_type [String] 'CALL' or 'PUT'
        # @return [Float] Delta value
        def self.calculate(
          spot_price:, strike_price:, time_to_expiry:,
          risk_free_rate:, volatility:, option_type: OptionsTrader::CALL
        )
          d1_val = BlackScholes.d1(spot_price, strike_price, time_to_expiry, risk_free_rate, volatility)

          case option_type
          when OptionsTrader::CALL
            BlackScholes.norm_cdf(d1_val)
          when OptionsTrader::PUT
            BlackScholes.norm_cdf(d1_val) - 1.0
          else
            raise ArgumentError, "option_type must be 'CALL' or 'PUT'"
          end
        end

        # Calculate option delta using Cox-Ross-Rubinstein numerical differentiation
        # @param spot_price [Float] Current price of underlying asset
        # @param strike_price [Float] Option strike price
        # @param time_to_expiry [Float] Time to expiration in years
        # @param risk_free_rate [Float] Risk-free interest rate (as decimal)
        # @param volatility [Float] Implied volatility (as decimal)
        # @param option_type [String] 'CALL' or 'PUT'
        # @param dividend_yield [Float] Annualized dividend yield (default 0)
        # @return [Float] Delta value
        def self.calculate_crr(
          spot_price:, strike_price:, time_to_expiry:,
          risk_free_rate:, volatility:, option_type: OptionsTrader::CALL,
          dividend_yield: 0.0
        )
          # Small bump in underlying price (1% of spot price, minimum $0.01)
          delta_s = [spot_price * 0.015, 0.01].max

          # Calculate option prices at S+ΔS and S-ΔS using CRR model
          price_up = CoxRossRubinstein.calculate(
            spot_price: spot_price + delta_s,
            strike_price: strike_price,
            time_to_expiry: time_to_expiry,
            risk_free_rate: risk_free_rate,
            volatility: volatility,
            option_type: option_type,
            dividend_yield: dividend_yield
          )

          price_down = CoxRossRubinstein.calculate(
            spot_price: spot_price - delta_s,
            strike_price: strike_price,
            time_to_expiry: time_to_expiry,
            risk_free_rate: risk_free_rate,
            volatility: volatility,
            option_type: option_type,
            dividend_yield: dividend_yield
          )

          # Calculate delta using central difference method
          (price_up - price_down) / (2.0 * delta_s)
        end
      end

      class Gamma
        # Calculate option gamma using Black-Scholes
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

        # Calculate option gamma using CRR numerical differentiation
        # Gamma = (Delta(S+ΔS) - Delta(S-ΔS)) / (2×ΔS)
        def self.calculate_crr(
          spot_price:, strike_price:, time_to_expiry:,
          risk_free_rate:, volatility:, option_type: OptionsTrader::CALL,
          dividend_yield: 0.0
        )
          delta_s = [spot_price * 0.01, 0.01].max

          delta_up = Delta.calculate_crr(
            spot_price: spot_price + delta_s,
            strike_price: strike_price,
            time_to_expiry: time_to_expiry,
            risk_free_rate: risk_free_rate,
            volatility: volatility,
            option_type: option_type,
            dividend_yield: dividend_yield
          )

          delta_down = Delta.calculate_crr(
            spot_price: spot_price - delta_s,
            strike_price: strike_price,
            time_to_expiry: time_to_expiry,
            risk_free_rate: risk_free_rate,
            volatility: volatility,
            option_type: option_type,
            dividend_yield: dividend_yield
          )

          (delta_up - delta_down) / (2.0 * delta_s)
        end
      end

      class Vega
        # Calculate option vega using Black-Scholes
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

        # Calculate option vega using CRR numerical differentiation
        # Vega = (V(σ+Δσ) - V(σ-Δσ)) / (2×Δσ)
        def self.calculate_crr(
          spot_price:, strike_price:, time_to_expiry:,
          risk_free_rate:, volatility:, option_type: OptionsTrader::CALL,
          dividend_yield: 0.0
        )
          delta_vol = 0.01  # 1% volatility bump

          price_up = CoxRossRubinstein.calculate(
            spot_price: spot_price,
            strike_price: strike_price,
            time_to_expiry: time_to_expiry,
            risk_free_rate: risk_free_rate,
            volatility: volatility + delta_vol,
            option_type: option_type,
            dividend_yield: dividend_yield
          )

          price_down = CoxRossRubinstein.calculate(
            spot_price: spot_price,
            strike_price: strike_price,
            time_to_expiry: time_to_expiry,
            risk_free_rate: risk_free_rate,
            volatility: volatility - delta_vol,
            option_type: option_type,
            dividend_yield: dividend_yield
          )

          (price_up - price_down) / (2.0 * delta_vol)
        end
      end

      class Theta
        # Calculate option theta (time decay) using Black-Scholes
        # @param spot_price [Float] Current price of underlying asset
        # @param strike_price [Float] Option strike price
        # @param time_to_expiry [Float] Time to expiration in years
        # @param risk_free_rate [Float] Risk-free interest rate (as decimal)
        # @param volatility [Float] Implied volatility (as decimal)
        # @param option_type [String] 'CALL' or 'PUT'
        # @return [Float] Theta value (typically negative)
        def self.calculate(
          spot_price:, strike_price:, time_to_expiry:,
          risk_free_rate:, volatility:, option_type: OptionsTrader::CALL
        )
          d1_val = BlackScholes.d1(spot_price, strike_price, time_to_expiry, risk_free_rate, volatility)
          d2_val = BlackScholes.d2(spot_price, strike_price, time_to_expiry, risk_free_rate, volatility)

          first_term = -(spot_price * BlackScholes.norm_pdf(d1_val) * volatility) / (2.0 * Math.sqrt(time_to_expiry))

          case option_type
          when OptionsTrader::CALL
            second_term = -risk_free_rate * strike_price *
                         Math.exp(-risk_free_rate * time_to_expiry) *
                         BlackScholes.norm_cdf(d2_val)
          when OptionsTrader::PUT
            second_term = risk_free_rate * strike_price *
                         Math.exp(-risk_free_rate * time_to_expiry) *
                         BlackScholes.norm_cdf(-d2_val)
          else
            raise ArgumentError, "option_type must be CALL or PUT"
          end

          first_term + second_term
        end

        # Calculate option theta using CRR numerical differentiation
        # Theta = (V(T-ΔT) - V(T)) / ΔT (note: negative because time decreases)
        def self.calculate_crr(
          spot_price:, strike_price:, time_to_expiry:,
          risk_free_rate:, volatility:, option_type: OptionsTrader::CALL,
          dividend_yield: 0.0
        )
          delta_time = 1.0 / 365.0  # 1 day in years

          # Ensure we don't go negative on time
          return 0.0 if time_to_expiry <= delta_time

          price_current = CoxRossRubinstein.calculate(
            spot_price: spot_price,
            strike_price: strike_price,
            time_to_expiry: time_to_expiry,
            risk_free_rate: risk_free_rate,
            volatility: volatility,
            option_type: option_type,
            dividend_yield: dividend_yield
          )

          price_tomorrow = CoxRossRubinstein.calculate(
            spot_price: spot_price,
            strike_price: strike_price,
            time_to_expiry: time_to_expiry - delta_time,
            risk_free_rate: risk_free_rate,
            volatility: volatility,
            option_type: option_type,
            dividend_yield: dividend_yield
          )

          # Theta is the change in option value per unit time decrease
          (price_tomorrow - price_current) / delta_time
        end
      end

      class Rho
        # Calculate option rho (interest rate sensitivity) using Black-Scholes
        # @param spot_price [Float] Current price of underlying asset
        # @param strike_price [Float] Option strike price
        # @param time_to_expiry [Float] Time to expiration in years
        # @param risk_free_rate [Float] Risk-free interest rate (as decimal)
        # @param volatility [Float] Implied volatility (as decimal)
        # @param option_type [String] 'CALL' or 'PUT'
        # @return [Float] Rho value
        def self.calculate(
          spot_price:, strike_price:, time_to_expiry:,
          risk_free_rate:, volatility:, option_type: OptionsTrader::CALL
        )
          d2_val = BlackScholes.d2(spot_price, strike_price, time_to_expiry, risk_free_rate, volatility)

          case option_type
          when OptionsTrader::CALL
            strike_price * time_to_expiry *
            Math.exp(-risk_free_rate * time_to_expiry) *
            BlackScholes.norm_cdf(d2_val)
          when OptionsTrader::PUT
            -strike_price * time_to_expiry *
            Math.exp(-risk_free_rate * time_to_expiry) *
            BlackScholes.norm_cdf(-d2_val)
          else
            raise ArgumentError, "option_type must be CALL or PUT"
          end
        end

        # Calculate option rho using CRR numerical differentiation
        # Rho = (V(r+Δr) - V(r-Δr)) / (2×Δr)
        def self.calculate_crr(
          spot_price:, strike_price:, time_to_expiry:,
          risk_free_rate:, volatility:, option_type: OptionsTrader::CALL,
          dividend_yield: 0.0
        )
          delta_rate = 0.0001  # 1 basis point (0.01%)

          price_up = CoxRossRubinstein.calculate(
            spot_price: spot_price,
            strike_price: strike_price,
            time_to_expiry: time_to_expiry,
            risk_free_rate: risk_free_rate + delta_rate,
            volatility: volatility,
            option_type: option_type,
            dividend_yield: dividend_yield
          )

          price_down = CoxRossRubinstein.calculate(
            spot_price: spot_price,
            strike_price: strike_price,
            time_to_expiry: time_to_expiry,
            risk_free_rate: risk_free_rate - delta_rate,
            volatility: volatility,
            option_type: option_type,
            dividend_yield: dividend_yield
          )

          (price_up - price_down) / (2.0 * delta_rate)
        end
      end
    end
  end
end
