module OptionsTrader
  module Utils
    class MonotonicityEnforcer
      # Enforces no-arbitrage monotonicity constraints on option prices
      # - Calls: mark[i] > mark[i+1] for all i (decreasing with strike)
      # - Puts: mark[i] < mark[i+1] for all i (increasing with strike)
      #
      # Returns a new array with enforced monotonicity
      #
      # @param options [Array] Array of option objects (must respond to :mark, :mark=, :strike)
      # @param contract_type [String] 'CALL' or 'PUT'
      # @return [Array] New array with enforced monotonicity
      def self.enforce(options, contract_type:)
        new(contract_type: contract_type).enforce(options)
      end

      MAX_ITERATIONS = 100
      MIN_PRICE = 0.01

      def initialize(contract_type:)
        @contract_type = contract_type
        @is_call = contract_type == 'CALL'
      end

      def enforce(options)
        # Create a copy of the options array to avoid modifying the original
        working_options = options.map(&:dup).sort_by { |o| o.strike }

        iteration = 0

        loop do
          violations = find_violations(working_options)
          break if violations.empty?

          iteration += 1
          break if iteration > MAX_ITERATIONS

          violation_ranges = group_contiguous_violations(violations)
          fix_violations(working_options, violation_ranges, violations)
        end

        working_options
      end

      private

      def find_violations(options)
        violations = []

        (0...options.length - 1).each do |i|
          if @is_call
            # Calls: current price should be > next price
            violations << i if options[i].mark <= options[i + 1].mark
          else
            # Puts: current price should be < next price
            violations << i if options[i].mark >= options[i + 1].mark
          end
        end

        violations
      end

      def group_contiguous_violations(violations)
        return [] if violations.empty?

        ranges = []
        current_range = [violations.first]

        violations.each_cons(2) do |v1, v2|
          if v2 == v1 + 1
            current_range << v2
          else
            ranges << current_range
            current_range = [v2]
          end
        end
        ranges << current_range if current_range.any?

        ranges
      end

      def fix_violations(options, violation_ranges, violations)
        violation_ranges.each do |range|
          start_idx = range.first
          end_idx = range.last + 1

          # Find the nearest non-violating options above and below
          lower_idx = find_lower_bound(start_idx, violations)
          upper_idx = find_upper_bound(end_idx, violations, options.length)

          # Get or estimate boundary prices
          lower_price = get_lower_boundary_price(options, lower_idx, upper_idx, start_idx)
          upper_price = get_upper_boundary_price(options, lower_idx, upper_idx, end_idx, options.length)

          # Apply linear interpolation to fix violations
          apply_interpolation(options, start_idx, end_idx, lower_price, upper_price)
        end
      end

      def find_lower_bound(start_idx, violations)
        lower_idx = start_idx - 1

        while lower_idx >= 0 && violations.include?(lower_idx)
          lower_idx -= 1
        end

        lower_idx
      end

      def find_upper_bound(end_idx, violations, options_length)
        upper_idx = end_idx + 1

        while upper_idx < options_length && violations.include?(upper_idx)
          upper_idx += 1
        end

        upper_idx
      end

      def get_lower_boundary_price(options, lower_idx, upper_idx, start_idx)
        if lower_idx < 0
          if upper_idx < options.length
            num_steps = start_idx + 1
            upper_price = options[upper_idx].mark
            if @is_call
              upper_price + (num_steps * MIN_PRICE)
            else
              MIN_PRICE
            end
          else
            @is_call ? 1.0 : MIN_PRICE
          end
        else
          options[lower_idx].mark
        end
      end

      def get_upper_boundary_price(options, lower_idx, upper_idx, end_idx, options_length)
        if upper_idx >= options_length
          if lower_idx >= 0
            num_steps = options_length - end_idx
            lower_price = options[lower_idx].mark
            if @is_call
              [lower_price - (num_steps * MIN_PRICE), MIN_PRICE].max
            else
              lower_price + (num_steps * MIN_PRICE)
            end
          else
            @is_call ? MIN_PRICE : 1.0
          end
        else
          options[upper_idx].mark
        end
      end

      def apply_interpolation(options, start_idx, end_idx, lower_price, upper_price)
        num_violating = end_idx - start_idx + 1
        price_diff = if @is_call
          lower_price - upper_price
        else
          upper_price - lower_price
        end

        # Ensure we have a positive step size
        if price_diff <= 0
          price_diff = num_violating * MIN_PRICE
          if @is_call
            upper_price = [lower_price - price_diff, MIN_PRICE].max
          else
            upper_price = lower_price + price_diff
          end
        end

        step_size = price_diff / (num_violating + 1.0)

        # Apply linear interpolation
        (start_idx..end_idx).each_with_index do |idx, step|
          new_price = if @is_call
            lower_price - (step + 1) * step_size
          else
            lower_price + (step + 1) * step_size
          end
          options[idx].mark = new_price
        end
      end
    end
  end
end
