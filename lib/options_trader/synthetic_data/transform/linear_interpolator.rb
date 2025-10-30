module OptionsTrader
  module SyntheticData
    module Transform
      class OptionsDifferentTypes < StandardError; end

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
        def self.interpolate(options, min_otm_extrinsic: 0.025, min_itm_extrinsic: 26.0)
          new(
            min_otm_extrinsic: min_otm_extrinsic,
            min_itm_extrinsic: min_itm_extrinsic
          ).interpolate(options)
        end

        def initialize(min_otm_extrinsic: 0.025, min_itm_extrinsic: 26.0)
          @min_otm_extrinsic = min_otm_extrinsic
          @min_itm_extrinsic = min_itm_extrinsic
        end

        def interpolate(options)
          raise OptionsDifferentTypes unless options.all? do |opt|
            opt.put_call == options[0].put_call
          end

          set_contract_type(options)

          sorted_opts = sort_options(options.map(&:dup))
          validate_options(sorted_opts)
          set_boundary_extrinsics!(sorted_opts)

          interpolate_extrinsic_values(sorted_opts)

          sorted_opts
        end

        def validate_options(options)
          underlying_price = options.first.underlying_price
          otm_opts = if @contract_type == OptionsTrader::CALL
                       options.select { |opt| opt.strike > underlying_price }
                     else
                       options.select { |opt| opt.strike < underlying_price }
                     end
          itm_opts = options - otm_opts

            # Ensure we have at least three OTM and three ITM options
            if otm_opts.length < 3 || itm_opts.length < 3
              raise "Options must include at least 3 OTM and 3 ITM options (got #{otm_opts.length} OTM, #{itm_opts.length} ITM)"
            end
        end

        # Set extrinsic for the most out-of-the-money (OTM) boundary option in the list.
        #
        # Calculation and intent:
        # - The extrinsic is computed as:
        #     (days_to_expiration / 3 + 1) * @min_extrinsic
        # - This is a heuristic to account for the empirical observation that the
        #   minimum extrinsic (time value) for even the most OTM options tends to
        #   increase as time to expiration increases. Scaling @min_extrinsic by a
        #   factor that grows with days_to_expiration raises the extrinsic floor for
        #   longer-dated options so the synthetic data better reflects time-value
        #   effects.
        #
        # Parameters:
        # - options: an ordered Array of option-like objects expected to respond to
        #   `put_call` and `days_to_expiration`, and to allow writing to `extrinsic`.
        #
        # Side effects:
        # - Mutates the `extrinsic` attribute of the chosen boundary option.
        #
        # Notes:
        # - The division by 3 and the +1 offset are intentionally heuristic; adjust
        #   these constants if you need a different time-value scaling behavior.
        def set_boundary_extrinsics!(options)
          most_otm_opt = options.first
          most_otm_opt.calc_mark_from_extrinsic((most_otm_opt.days_to_expiration / 3 + 1) * @min_otm_extrinsic) if most_otm_opt.mark.nil?

          most_itm_opt = options.last
          most_itm_opt.calc_mark_from_extrinsic(@min_itm_extrinsic) if most_itm_opt.mark.nil?
        end

        def set_contract_type(options)
          @contract_type ||= options.first.put_call
        end

        def sort_options(options)
          if @contract_type == OptionsTrader::CALL
            options.sort_by { |opt| -opt.strike }
          else
            options.sort_by(&:strike)
          end
        end

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
              # TODO: want to delete this condition since
              # the boundaries should be set already
              binding.pry
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
            options[i].calc_mark_from_extrinsic([0, interpolated_extrinsic].max)
          end
        end
      end
    end
  end
end
