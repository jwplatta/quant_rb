# frozen_string_literal: true

module QuantRb
  module Data
    module Pricing
      module BlackScholes
        module_function

        def price(spot:, strike:, tau_years:, sigma:, rate:, contract_type:)
          intrinsic = intrinsic_value(spot: spot, strike: strike, contract_type: contract_type)
          return intrinsic if tau_years <= 0.0 || sigma <= 0.0

          d1_value = d1(spot: spot, strike: strike, tau_years: tau_years, sigma: sigma, rate: rate)
          d2_value = d1_value - sigma * Math.sqrt(tau_years)
          discount = Math.exp(-rate * tau_years)

          if call_contract?(contract_type)
            (spot * normal_cdf(d1_value)) - (strike * discount * normal_cdf(d2_value))
          else
            (strike * discount * normal_cdf(-d2_value)) - (spot * normal_cdf(-d1_value))
          end
        end

        def delta(spot:, strike:, tau_years:, sigma:, rate:, contract_type:)
          return(call_contract?(contract_type) ? (spot > strike ? 1.0 : 0.0) : (spot < strike ? -1.0 : 0.0)) if tau_years <= 0.0 || sigma <= 0.0

          d1_value = d1(spot: spot, strike: strike, tau_years: tau_years, sigma: sigma, rate: rate)
          call_contract?(contract_type) ? normal_cdf(d1_value) : (normal_cdf(d1_value) - 1.0)
        end

        def gamma(spot:, strike:, tau_years:, sigma:, rate:)
          return 0.0 if tau_years <= 0.0 || sigma <= 0.0 || spot <= 0.0

          d1_value = d1(spot: spot, strike: strike, tau_years: tau_years, sigma: sigma, rate: rate)
          normal_pdf(d1_value) / (spot * sigma * Math.sqrt(tau_years))
        end

        def theta(spot:, strike:, tau_years:, sigma:, rate:, contract_type:)
          return 0.0 if tau_years <= 0.0 || sigma <= 0.0

          d1_value = d1(spot: spot, strike: strike, tau_years: tau_years, sigma: sigma, rate: rate)
          d2_value = d1_value - sigma * Math.sqrt(tau_years)
          first_term = -(spot * normal_pdf(d1_value) * sigma) / (2.0 * Math.sqrt(tau_years))

          if call_contract?(contract_type)
            first_term - (rate * strike * Math.exp(-rate * tau_years) * normal_cdf(d2_value))
          else
            first_term + (rate * strike * Math.exp(-rate * tau_years) * normal_cdf(-d2_value))
          end
        end

        def vega(spot:, strike:, tau_years:, sigma:, rate:)
          return 0.0 if tau_years <= 0.0 || sigma <= 0.0

          d1_value = d1(spot: spot, strike: strike, tau_years: tau_years, sigma: sigma, rate: rate)
          spot * normal_pdf(d1_value) * Math.sqrt(tau_years)
        end

        def rho(spot:, strike:, tau_years:, sigma:, rate:, contract_type:)
          return 0.0 if tau_years <= 0.0 || sigma <= 0.0

          d1_value = d1(spot: spot, strike: strike, tau_years: tau_years, sigma: sigma, rate: rate)
          d2_value = d1_value - sigma * Math.sqrt(tau_years)

          if call_contract?(contract_type)
            strike * tau_years * Math.exp(-rate * tau_years) * normal_cdf(d2_value)
          else
            -strike * tau_years * Math.exp(-rate * tau_years) * normal_cdf(-d2_value)
          end
        end

        def intrinsic_value(spot:, strike:, contract_type:)
          if call_contract?(contract_type)
            [spot - strike, 0.0].max
          else
            [strike - spot, 0.0].max
          end
        end

        def d1(spot:, strike:, tau_years:, sigma:, rate:)
          numerator = Math.log(spot / strike) + ((rate + 0.5 * sigma * sigma) * tau_years)
          denominator = sigma * Math.sqrt(tau_years)
          numerator / denominator
        end

        def normal_cdf(value)
          0.5 * (1.0 + Math.erf(value / Math.sqrt(2.0)))
        end

        def normal_pdf(value)
          Math.exp(-(value**2) / 2.0) / Math.sqrt(2.0 * Math::PI)
        end

        def call_contract?(contract_type)
          contract_type.to_s.upcase == QuantRb::CALL
        end
      end
    end
  end
end
