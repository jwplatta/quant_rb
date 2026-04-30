# frozen_string_literal: true

module QuantRb
  module Data
    module Pricing
      module ImpliedVolatilitySolver
        module_function

        def solve(market_price:, spot:, strike:, tau_years:, rate:, contract_type:, pricing_model: :black_scholes, tolerance: 1e-5, low: 0.0001, high: 5.0, max_iterations: 100)
          intrinsic = BlackScholes.intrinsic_value(spot: spot, strike: strike, contract_type: contract_type)
          target = [market_price.to_f, intrinsic].max

          low_value = price_for_sigma(pricing_model, spot:, strike:, tau_years:, sigma: low, rate:, contract_type:) - target
          high_value = price_for_sigma(pricing_model, spot:, strike:, tau_years:, sigma: high, rate:, contract_type:) - target
          return nil if low_value.zero?
          return nil if high_value.zero?
          return nil if low_value * high_value > 0

          current_low = low
          current_high = high

          max_iterations.times do
            mid = 0.5 * (current_low + current_high)
            value = price_for_sigma(pricing_model, spot:, strike:, tau_years:, sigma: mid, rate:, contract_type:) - target
            return mid if value.abs <= tolerance

            if low_value * value < 0
              current_high = mid
              high_value = value
            else
              current_low = mid
              low_value = value
            end
          end

          0.5 * (current_low + current_high)
        end

        def price_for_sigma(pricing_model, **args)
          case pricing_model.to_sym
          when :black_scholes
            BlackScholes.price(**args)
          when :binomial, :crr
            CrrBinomial.price(**args)
          else
            raise ArgumentError, "Unsupported pricing model: #{pricing_model}"
          end
        end
      end
    end
  end
end
