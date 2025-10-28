module OptionsTrader
  module SyntheticData
    module Validators
      class MonotonicityViolationError < StandardError; end

      class Monotonicity
        # Verifies that mark monotonicity is satisfied across all options.
        # Raises an error if any violations are found.
        #
        # For calls: sorts by ascending strike and verifies marks are non-increasing
        # For puts: sorts by descending strike and verifies marks are non-increasing
        #
        # @param options [Array<DataObjects::Option>] Options to check
        # @raise [MonotonicityViolationError] If mark monotonicity is violated
        def self.check(options)
          if options.first.put_call == OptionsTrader::CALL
            sorted_opts = options.sort_by(&:strike)
            compare_marks(sorted_opts)
          elsif options.first.put_call == OptionsTrader::PUT
            sorted_opts = options.sort_by(&:strike).reverse
            compare_marks(sorted_opts)
          else
            raise ArgumentError, "Unknown contract type: #{options.first.put_call}"
          end

          true
        end

        # Compares consecutive option marks to detect violations.
        # Assumes options are already sorted in the correct order for their contract type.
        #
        # Uses a two-pointer algorithm that skips over options with nil marks.
        #
        # @param options [Array<DataObjects::Option>] Pre-sorted options
        # @raise [MonotonicityViolationError] If curr_mark < next_mark
        def self.compare_marks(options)
          # NOTE: assumes options are sorted
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
              raise MonotonicityViolationError, "At strikes: #{options[curr_idx].strike} and #{options[next_idx].strike}"
            else
              curr_idx = next_idx
              next_idx += 1
            end

            break if next_idx >= options.length
          end
        end
      end
    end
  end
end
