module OptionsTrader
  module SyntheticData
    module Transform
      class MonotonicityViolationError < StandardError; end

      class MonotonicityEnforcer
        # Enforces no-arbitrage monotonicity constraints on option prices.
        #
        # This class implements a two-phase approach to enforcing monotonicity:
        # 1. First pass: Fix extrinsic value monotonicity violations separately for OTM and ITM options
        # 2. Second pass: Verify mark monotonicity across all options and raise if violations remain
        #
        # Monotonicity rules:
        # - Calls: mark must decrease (or stay equal) with increasing strike
        # - Puts: mark must increase (or stay equal) with increasing strike
        # - Extrinsic value: must decrease moving away from ATM in both directions
        #   - OTM calls: extrinsic decreases as strike increases (moving further OTM)
        #   - ITM calls: extrinsic decreases as strike decreases (moving further ITM)
        #   - OTM puts: extrinsic decreases as strike decreases (moving further OTM)
        #   - ITM puts: extrinsic decreases as strike increases (moving further ITM)
        #
        # Method modes:
        # - 'remove': Sets violating option marks to nil (default and only mode supported)
        #
        # @param options [Array<DataObjects::Option>] Array of option objects (all same contract type)
        # @param underlying_price [Float] Current price of the underlying asset
        # @param method [String] 'remove' (only mode supported for now)
        # @return [Array<DataObjects::Option>] Array with enforced monotonicity (violations set to nil)
        # @raise [MonotonicityViolationError] If unresolvable mark violations remain after fixing extrinsic
        def self.enforce(options, underlying_price, method: 'remove')
          new(
            underlying_price: underlying_price,
            method: method
          ).enforce(options)
        end

        # @param underlying_price [Float] Current price of the underlying asset
        # @param method [String] Enforcement method ('remove' is the only supported mode)
        def initialize(underlying_price:, method: 'remove')
          @underlying_price = underlying_price
          @method = method
        end

        # Main enforcement method that applies monotonicity constraints.
        #
        # Algorithm:
        # 1. Validates all options are the same contract type
        # 2. Duplicates options to avoid mutating originals
        # 3. Fixes extrinsic value violations separately for OTM and ITM options
        # 4. Checks final mark monotonicity and raises if violations remain
        #
        # @param options [Array<DataObjects::Option>] Array of option objects
        # @return [Array<DataObjects::Option>] Options with monotonicity enforced
        # @raise [StandardError] If options have mixed contract types
        # @raise [MonotonicityViolationError] If unresolvable mark violations exist
        def enforce(options)
          return [] if options.empty?
          return options if options.length == 1

          @contract_type = options.first.put_call
          options.all? { |opt| opt.put_call == @contract_type } ||
            raise("All options must be of contract type #{@contract_type}")

          working_options = options.map(&:dup)

          checked_opts = if is_call?
            fix_otm_calls(working_options) + fix_itm_calls(working_options)
          else
            fix_otm_puts(working_options) + fix_itm_puts(working_options)
          end

          check_monotonicity(checked_opts)

          checked_opts
        end

        # Verifies that mark monotonicity is satisfied across all options.
        # Raises an error if any violations are found.
        #
        # For calls: sorts by ascending strike and verifies marks are non-increasing
        # For puts: sorts by descending strike and verifies marks are non-increasing
        #
        # @param options [Array<DataObjects::Option>] Options to check
        # @raise [MonotonicityViolationError] If mark monotonicity is violated
        def check_monotonicity(options)
          if is_call?
            sorted_opts = options.sort_by(&:strike)
            compare_marks(sorted_opts)
          else
            sorted_opts = options.sort_by(&:strike).reverse
            compare_marks(sorted_opts)
          end
        end

        # Compares consecutive option marks to detect violations.
        # Assumes options are already sorted in the correct order for their contract type.
        #
        # Uses a two-pointer algorithm that skips over options with nil marks.
        #
        # @param options [Array<DataObjects::Option>] Pre-sorted options
        # @raise [MonotonicityViolationError] If curr_mark < next_mark
        def compare_marks(options)
          # NOTE: assumes options are sortd
          curr_idx = 0
          next_idx = 1

          while true
            curr_mark = options[curr_idx].mark
            next_mark = options[next_idx].mark

            if curr_mark.nil?
              curr_idx = next_idx
              next_idx += 1
            elsif next_mark.nil?
              next_idx += 1
            elsif curr_mark < next_mark
              raise MonotonicityViolationError, "CALL at strikes: #{options[curr_idx].strike} and #{options[next_idx].strike}"
            else
              curr_idx = next_idx
              next_idx += 1
            end

            break if next_idx >= options.length
          end
        end

        # Fixes extrinsic value violations in out-of-the-money call options.
        #
        # OTM calls have strikes above the underlying price. Their extrinsic value
        # should decrease as strike increases (moving further OTM).
        #
        # @param call_opts [Array<DataObjects::Option>] Call options
        # @return [Array<DataObjects::Option>] OTM calls with violations removed
        def fix_otm_calls(call_opts)
          otm_opts = call_opts
            .select { |opt| opt.strike > @underlying_price }
            .sort_by(&:strike)

          return [] if otm_opts.empty?
          return otm_opts if otm_opts.length == 1

          fix_extrinsic(otm_opts, :check_non_increase)
        end

        # Fixes extrinsic value violations in in-the-money call options.
        #
        # ITM calls have strikes at or below the underlying price. Their extrinsic value
        # should decrease as strike decreases (moving further ITM).
        #
        # @param call_opts [Array<DataObjects::Option>] Call options
        # @return [Array<DataObjects::Option>] ITM calls with violations removed
        def fix_itm_calls(call_opts)
          itm_opts = call_opts
            .select { |opt| opt.strike <= @underlying_price }
            .sort_by(&:strike)

          return [] if itm_opts.empty?
          return itm_opts if itm_opts.length == 1

          fix_extrinsic(itm_opts, :check_non_decrease)
        end

        # Fixes extrinsic value violations in out-of-the-money put options.
        #
        # OTM puts have strikes below the underlying price. Their extrinsic value
        # should decrease as strike decreases (moving further OTM).
        #
        # @param put_opts [Array<DataObjects::Option>] Put options
        # @return [Array<DataObjects::Option>] OTM puts with violations removed
        def fix_otm_puts(put_opts)
          otm_opts = put_opts
            .select { |opt| opt.strike < @underlying_price }
            .sort_by(&:strike)

          return [] if otm_opts.empty?
          return otm_opts if otm_opts.length == 1

          fix_extrinsic(otm_opts, :check_non_decrease)
        end

        # Fixes extrinsic value violations in in-the-money put options.
        #
        # ITM puts have strikes at or above the underlying price. Their extrinsic value
        # should decrease as strike increases (moving further ITM).
        #
        # @param put_opts [Array<DataObjects::Option>] Put options
        # @return [Array<DataObjects::Option>] ITM puts with violations removed
        def fix_itm_puts(put_opts)
          itm_opts = put_opts
            .select { |opt| opt.strike >= @underlying_price }
            .sort_by(&:strike)

          return [] if itm_opts.empty?
          return itm_opts if itm_opts.length == 1

          fix_extrinsic(itm_opts, :check_non_increase)
        end

        # Detects and removes extrinsic value violations in a sorted array of options.
        #
        # Uses a two-pointer algorithm to compare consecutive extrinsic values.
        # When a violation is detected, the violating option's mark is set to nil.
        #
        # Algorithm:
        # 1. First pass: scan through options and collect indices of violations
        # 2. Second pass: reset price values for all violating options
        #
        # @param options [Array<DataObjects::Option>] Pre-sorted options (by strike)
        # @param violation_type [Symbol] Type of check to perform:
        #   - :check_non_increase - flags if curr < prev (extrinsic should not increase)
        #   - :check_non_decrease - flags if curr > prev (extrinsic should not decrease)
        # @return [Array<DataObjects::Option>] Options with violations removed
        def fix_extrinsic(options, violation_type)
          violations = []

          curr_val_idx = 0
          next_val_idx = 1

          while true

            curr_val = options[curr_val_idx].extrinsic
            next_val = options[next_val_idx].extrinsic

            if curr_val.nil?
              curr_val_idx = next_val_idx
              next_val_idx += 1
            elsif next_val.nil?
              next_val_idx += 1
            elsif is_violation?(curr_val, next_val, violation_type)
              violations << next_val_idx
              next_val_idx += 1
            else
              curr_val_idx = next_val_idx
              next_val_idx += 1
            end

            break if next_val_idx >= options.length
          end

          # Second pass: remove all violations at once
          violations.each do |idx|
            options[idx].reset_price_values!
          end

          options
        end

        # Determines if two consecutive values violate the specified monotonicity constraint.
        #
        # @param curr_val [Float, nil] Current value in sequence
        # @param prev_val [Float, nil] Previous value in sequence
        # @param violation_type [Symbol] Type of constraint to check:
        #   - :check_decrease - true if curr_val <= prev_val (should strictly decrease)
        #   - :check_non_increase - true if curr_val < prev_val (should not increase)
        #   - :check_increase - true if curr_val >= prev_val (should strictly increase)
        #   - :check_non_decrease - true if curr_val > prev_val (should not decrease)
        # @return [Boolean] true if violation detected, false otherwise
        # @raise [StandardError] If unknown violation_type provided
        def is_violation?(curr_val, prev_val, violation_type)
          return false if curr_val.nil? || prev_val.nil?

          if violation_type == :check_decrease
            curr_val <= prev_val
          elsif violation_type == :check_non_increase
            curr_val < prev_val
          elsif violation_type == :check_increase
            curr_val >= prev_val
          elsif violation_type == :check_non_decrease
            curr_val > prev_val
          else
            raise "Unknown violation type: #{violation_type}"
          end
        end

        def is_call?
          @contract_type == 'CALL'
        end
      end
    end
  end
end
