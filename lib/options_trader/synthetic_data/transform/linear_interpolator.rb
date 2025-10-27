module OptionsTrader
  module SyntheticData
    module Transform
      class LinearInterpolator
        # Interpolates option prices for options with nil marks
        # Uses extrinsic value interpolation for all options (ITM and OTM)
        # Returns a new array with interpolated prices
        #
        # Note: Monotonicity should be enforced before and/or after interpolation
        # via MonotonicityEnforcer as needed
        #
        # @param options [Array] Array of option objects (must respond to :mark, :extrinsic, :strike, :calc_mark_from_extrinsic)
        # @param contract_type [String] 'CALL' or 'PUT' (used for logging/context)
        # @param min_extrinsic [Float] Minimum extrinsic value (default: 0.025)
        # @return [Array] New array with interpolated prices
        def self.interpolate(options, contract_type:, min_extrinsic: 0.025)
          new(contract_type: contract_type, min_extrinsic: min_extrinsic).interpolate(options)
        end

        def initialize(contract_type:, min_extrinsic: 0.025)
          @contract_type = contract_type
          @min_extrinsic = min_extrinsic
        end

        def interpolate(options)
          # Create a copy to avoid modifying the original
          working_options = options.map(&:clone)

          # Interpolate all options using unified extrinsic interpolation
          interpolate_extrinsic_values(working_options)

          working_options
        end

        private

        def interpolate_extrinsic_values(options)
          idx = 0
          while idx < options.length
            # Skip options that already have marks
            if options[idx].mark
              idx += 1
              next
            end

            # Found a nil mark - find the sequence of consecutive nils
            start_idx = idx
            end_idx = idx
            while end_idx < options.length && options[end_idx].mark.nil?
              end_idx += 1
            end
            end_idx -= 1  # Back up to last nil

            # Find bounds for interpolation
            lower_idx = (0...start_idx).reverse_each.find { |i| options[i].mark }
            upper_idx = ((end_idx + 1)...options.length).find { |i| options[i].mark }

            if lower_idx && upper_idx
              # Interpolate extrinsic values for the entire sequence
              interpolate_extrinsic_sequence(options, lower_idx, upper_idx, start_idx, end_idx)
            elsif lower_idx || upper_idx
              # Use minimum extrinsic for all in sequence
              (start_idx..end_idx).each do |i|
                options[i].calc_mark_from_extrinsic(@min_extrinsic)
              end
            else
              raise "Cannot interpolate options at strikes #{options[start_idx].strike}-#{options[end_idx].strike} (no bounds found)"
            end

            # Move past this sequence
            idx = end_idx + 1
          end
        end

        # Interpolate extrinsic values for a sequence of options with nil marks
        # Uses linear interpolation based on strike distance
        def interpolate_extrinsic_sequence(options, lower_idx, upper_idx, start_idx, end_idx)
          lower_opt = options[lower_idx]
          upper_opt = options[upper_idx]

          # Get extrinsic values from bounds
          lower_extrinsic = lower_opt.extrinsic
          upper_extrinsic = upper_opt.extrinsic

          # Calculate slope based on strike difference
          extrinsic_diff = upper_extrinsic - lower_extrinsic
          strike_diff = upper_opt.strike - lower_opt.strike
          slope = extrinsic_diff / strike_diff.to_f

          # Interpolate extrinsic for each option in the sequence
          (start_idx..end_idx).each do |i|
            strike_offset = options[i].strike - lower_opt.strike
            interpolated_extrinsic = lower_extrinsic + (slope * strike_offset)
            options[i].calc_mark_from_extrinsic([@min_extrinsic, interpolated_extrinsic].max)
          end
        end
      end
    end
  end
end
