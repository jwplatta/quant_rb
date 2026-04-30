# frozen_string_literal: true

module QuantRb
  module Data
    module Pricing
      <<~DOC
        Cox-Ross-Rubinstein binomial pricing for vanilla European-style options.

        Assumptions:
        - Time to expiry is expressed in years.
        - The input volatility and risk-free rate are annualized.
        - This implementation prices plain-vanilla call/put payoffs only.
        - Early exercise is not modeled, so this currently behaves like a European tree.

        Shortcuts in this Stage 1 implementation:
        - Terminal and intrinsic payoffs reuse `BlackScholes.intrinsic_value` because payoff
          shape is model-independent for vanilla options.
        - Delta is approximated by finite-differencing two CRR prices around spot instead of
          extracting delta directly from the first tree step. That is simpler, but less exact
          than a native tree-derived delta.
      DOC
      module CrrBinomial
        DEFAULT_STEPS = 100

        module_function

        def price(spot:, strike:, tau_years:, sigma:, rate:, contract_type:, steps: DEFAULT_STEPS)
          intrinsic = BlackScholes.intrinsic_value(spot: spot, strike: strike, contract_type: contract_type)
          return intrinsic if tau_years <= 0.0 || sigma <= 0.0

          dt = tau_years / steps.to_f
          u = Math.exp(sigma * Math.sqrt(dt))
          d = 1.0 / u
          p = (Math.exp(rate * dt) - d) / (u - d)
          discount = Math.exp(-rate * dt)

          values = Array.new(steps + 1) do |j|
            terminal_spot = spot * (u**j) * (d**(steps - j))
            BlackScholes.intrinsic_value(spot: terminal_spot, strike: strike, contract_type: contract_type)
          end

          (steps - 1).downto(0) do |i|
            0.upto(i) do |j|
              values[j] = discount * ((p * values[j + 1]) + ((1.0 - p) * values[j]))
            end
          end

          values[0]
        end

        def delta(spot:, strike:, tau_years:, sigma:, rate:, contract_type:, step_size: 0.5)
          up = price(spot: spot + step_size, strike: strike, tau_years: tau_years, sigma: sigma, rate: rate, contract_type: contract_type)
          down = price(spot: spot - step_size, strike: strike, tau_years: tau_years, sigma: sigma, rate: rate, contract_type: contract_type)
          (up - down) / (2.0 * step_size)
        end
      end
    end
  end
end
