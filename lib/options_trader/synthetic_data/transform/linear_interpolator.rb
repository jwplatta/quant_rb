module OptionsTrader
  module SyntheticData
    module Transform
      class LinearInterpolator
        # Interpolates option prices for options with nil marks
        # Assumes input prices are already monotonic - will raise error if not
        # Returns a new array with interpolated prices
        #
        # @param options [Array] Array of option objects (must respond to :mark, :mark=, :strike, :in_the_money?)
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

          # Verify monotonicity of existing prices
          verify_monotonicity!(working_options)

          # Separate into ITM and OTM
          itm_options = working_options.select(&:in_the_money?)
          otm_options = working_options.reject(&:in_the_money?)

          # Interpolate OTM options (price = extrinsic value)
          interpolate_otm_options(otm_options)

          # Interpolate ITM options (interpolate extrinsic, then set it)
          interpolate_itm_options(itm_options)

          working_options
        end

        private

        def verify_monotonicity!(options)
          # Check instance variable @mark directly to avoid triggering calculations
          options_with_marks = options.select { |opt| opt.instance_variable_get(:@mark) }
          return if options_with_marks.length < 2

          (0...options_with_marks.length - 1).each do |i|
            current = options_with_marks[i]
            next_opt = options_with_marks[i + 1]

            current_mark = current.instance_variable_get(:@mark)
            next_mark = next_opt.instance_variable_get(:@mark)

            # For calls: price should decrease as strike increases
            # For puts: price should increase as strike increases
            if @contract_type == 'CALL'
              if current_mark < next_mark
                raise "Non-monotonic prices detected: strike #{current.strike} has mark #{current_mark}, " \
                      "but strike #{next_opt.strike} has mark #{next_mark}"
              end
            else # PUT
              if current_mark > next_mark
                raise "Non-monotonic prices detected: strike #{current.strike} has mark #{current_mark}, " \
                      "but strike #{next_opt.strike} has mark #{next_mark}"
              end
            end
          end
        end

        def interpolate_otm_options(otm_options)
          otm_options.each_with_index do |opt, idx|
            # Check instance variable directly
            next unless opt.instance_variable_get(:@mark).nil?

            # Find lower and upper bounds (check instance variable directly)
            lower_idx = (0...idx).reverse_each.find { |i| otm_options[i].instance_variable_get(:@mark) }
            upper_idx = ((idx + 1)...otm_options.length).find { |i| otm_options[i].instance_variable_get(:@mark) }

            opt.mark = if lower_idx && upper_idx
              # Linear interpolation
              interpolate_between(otm_options[lower_idx], otm_options[upper_idx], opt.strike)
            elsif lower_idx || upper_idx
              # Use minimum extrinsic if we only have one bound
              @min_extrinsic
            else
              raise "Cannot interpolate option at strike #{opt.strike} (no bounds found)"
            end

            # Ensure minimum extrinsic value
            opt.mark = [@min_extrinsic, opt.mark].max
          end
        end

        def interpolate_itm_options(itm_options)
          itm_options.each_with_index do |opt, idx|
            # Check instance variable directly
            next unless opt.instance_variable_get(:@mark).nil?

            # Find lower and upper bounds (check instance variable directly)
            lower_idx = (0...idx).reverse_each.find { |i| itm_options[i].instance_variable_get(:@mark) }
            upper_idx = ((idx + 1)...itm_options.length).find { |i| itm_options[i].instance_variable_get(:@mark) }

            extrinsic_value = if lower_idx && upper_idx
              # Get extrinsic values from bounds
              lower_opt = itm_options[lower_idx]
              upper_opt = itm_options[upper_idx]

              # Interpolate extrinsic value
              interpolate_between_extrinsic(lower_opt, upper_opt, opt.strike)
            elsif lower_idx || upper_idx
              # Use minimum extrinsic if we only have one bound
              @min_extrinsic
            else
              raise "Cannot interpolate option at strike #{opt.strike} (no bounds found)"
            end

            # Ensure minimum extrinsic value
            extrinsic_value = [@min_extrinsic, extrinsic_value].max

            # Set extrinsic value and calculate mark from it
            opt.extrinsic = extrinsic_value
            opt.calculate_values!
          end
        end

        def interpolate_between(lower_opt, upper_opt, target_strike)
          # Linear interpolation between two points
          price_diff = upper_opt.mark - lower_opt.mark
          strike_diff = upper_opt.strike - lower_opt.strike
          slope = price_diff / strike_diff.to_f

          strike_offset = target_strike - lower_opt.strike
          lower_opt.mark + (slope * strike_offset)
        end

        def interpolate_between_extrinsic(lower_opt, upper_opt, target_strike)
          # Linear interpolation of extrinsic values
          lower_extrinsic = lower_opt.extrinsic
          upper_extrinsic = upper_opt.extrinsic

          extrinsic_diff = upper_extrinsic - lower_extrinsic
          strike_diff = upper_opt.strike - lower_opt.strike
          slope = extrinsic_diff / strike_diff.to_f

          strike_offset = target_strike - lower_opt.strike
          lower_extrinsic + (slope * strike_offset)
        end
      end
    end
  end
end
