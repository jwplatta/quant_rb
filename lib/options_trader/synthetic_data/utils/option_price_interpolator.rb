module OptionsTrader
  module SyntheticData
    module Utils
      class OptionPriceInterpolator
        # Interpolates and extrapolates option prices for options with nil marks
        # Returns a new array with interpolated prices
        #
        # @param options [Array] Array of option objects (must respond to :mark, :mark=, :strike)
        # @param contract_type [String] 'CALL' or 'PUT' (used for logging/context)
        # @return [Array] New array with interpolated prices
        def self.interpolate(options, contract_type:)
          new(contract_type: contract_type).interpolate(options)
        end

        def initialize(contract_type:)
          @contract_type = contract_type
        end

        def interpolate(options)
          # Create a copy to avoid modifying the original
          # Use clone instead of dup to preserve singleton methods (e.g., dynamic features)
          working_options = options.map(&:clone)

          working_options.each_with_index do |opt, idx|
            next unless opt.mark.nil?

            # Find lower bound (last option before this with non-nil mark)
            lower_idx = (0...idx).reverse_each.find { |i| working_options[i].mark }

            # Find upper bound (next option after this with non-nil mark)
            upper_idx = ((idx + 1)...working_options.length).find { |i| working_options[i].mark }

            opt.mark = if lower_idx && upper_idx
              # Interpolate between bounds
              interpolate_between_bounds(working_options, lower_idx, upper_idx, opt.strike)
            elsif lower_idx
              # Extrapolate using slope from last two points
              extrapolate_from_lower_bound(working_options, lower_idx, opt.strike)
            elsif upper_idx
              # Extrapolate using slope from first two points
              extrapolate_from_upper_bound(working_options, upper_idx, opt.strike)
            else
              raise "Cannot interpolate option at strike #{opt.strike} (no bounds found)"
            end
          end

          working_options
        end

        private

        def interpolate_between_bounds(options, lower_idx, upper_idx, target_strike)
          lower_opt = options[lower_idx]
          upper_opt = options[upper_idx]

          # Calculate step size
          price_diff = upper_opt.mark - lower_opt.mark
          strike_diff = upper_opt.strike - lower_opt.strike
          step_size = price_diff / strike_diff.to_f

          strike_offset = target_strike - lower_opt.strike
          lower_opt.mark + (step_size * strike_offset)
        end

        def extrapolate_from_lower_bound(options, lower_idx, target_strike)
          if lower_idx > 0
            # Find previous point with mark
            prev_opt_idx = (0...lower_idx).reverse_each.find { |i| options[i].mark }
            prev_opt = options[prev_opt_idx]
            lower_opt = options[lower_idx]

            price_diff = lower_opt.mark - prev_opt.mark
            strike_diff = lower_opt.strike - prev_opt.strike
            step_size = price_diff / strike_diff.to_f

            strike_offset = target_strike - lower_opt.strike
            lower_opt.mark + (step_size * strike_offset)
          else
            # Only one point, use it as constant
            options[lower_idx].mark
          end
        end

        def extrapolate_from_upper_bound(options, upper_idx, target_strike)
          if upper_idx < options.length - 1
            # Find next point with mark
            upper_opt = options[upper_idx]
            next_opt_idx = ((upper_idx + 1)...options.length).find { |i| options[i].mark }
            next_opt = options[next_opt_idx]

            price_diff = next_opt.mark - upper_opt.mark
            strike_diff = next_opt.strike - upper_opt.strike
            step_size = price_diff / strike_diff.to_f

            strike_offset = target_strike - upper_opt.strike
            upper_opt.mark + (step_size * strike_offset)
          else
            # Only one point, use it as constant
            options[upper_idx].mark
          end
        end
      end
    end
  end
end
