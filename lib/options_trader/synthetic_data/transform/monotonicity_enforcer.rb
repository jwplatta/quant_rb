module OptionsTrader
  module SyntheticData
    module Transform
      class MonotonicityEnforcer
        # Enforces no-arbitrage monotonicity constraints on option prices
        # - Calls: mark decreases with increasing strike
        # - Puts: mark increases with increasing strike
        # - Extrinsic value: decreases moving away from ATM in both directions
        #
        # Method modes:
        # - 'remove': Sets violating option marks to nil (default)
        #
        # @param options [Array] Array of option objects
        # @param contract_type [String] 'CALL' or 'PUT'
        # @param method [String] 'remove' (only mode supported for now)
        # @return [Array] New array with enforced monotonicity
        def self.enforce(options, contract_type:, method: 'remove')
          new(contract_type: contract_type, method: method).enforce(options)
        end

        def initialize(contract_type:, method: 'remove')
          @contract_type = contract_type
          @method = method
        end

        def enforce(options)
          return [] if options.empty?
          return options if options.length == 1

          # Create a copy to avoid modifying the original
          working_options = options.map(&:clone)

          # Enforce monotonicity on marks
          enforce_mark_monotonicity(working_options)

          working_options
        end

        private

        # Enforce monotonicity on mark/price
        # For CALLS: marks should decrease as strikes increase
        # For PUTS: marks should increase as strikes increase
        def enforce_mark_monotonicity(options)
          if is_call?
            # For calls: as strikes increase, marks should decrease
            enforce_mark(options.sort_by(&:strike))
          else
            # For puts: as strikes increase, marks should increase
            enforce_mark(options.sort_by(&:strike))
          end
        end

        # Enforce that values are strictly decreasing (each value < previous value)
        def enforce_mark(options)
          violations = []

          curr_val_idx = 0
          next_val_idx = 1

          while true
            curr_val = options[curr_val_idx].mark
            next_val = options[next_val_idx].mark

            if is_violation?(curr_val, next_val)
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
        end

        def is_violation?(curr_val, prev_val)
          return false if curr_val.nil? || prev_val.nil?

          if is_call?
            curr_val < prev_val
          else
            curr_val > prev_val
          end
        end

        def is_call?
          @contract_type.upcase == 'CALL'
        end
      end
    end
  end
end
