module OptionsTrader
  module SyntheticData
    module Transform
      class MonotonicityEnforcer
        class MissingUnderlyingPriceError < StandardError; end

        # Enforces no-arbitrage monotonicity constraints on option prices
        # - Calls: mark[i] > mark[i+1] for all i (decreasing with strike)
        # - Puts: mark[i] < mark[i+1] for all i (increasing with strike)
        #
        # Method modes:
        # - 'adjust': Fixes violations by adjusting prices (default behavior)
        # - 'remove': Sets violating option marks to nil, working from ATM strike
        #
        # Adjust strategy:
        # 1. If violation is close to neighbors (within threshold %), copy neighbor price
        # 2. Try open_price, high_price, low_price if available
        # 3. Try average of OHLC prices
        # 4. Use midpoint between neighbors as last resort
        # 5. Iteratively re-check for new violations
        #
        # Remove strategy:
        # For PUTs: Start at ATM, work towards OTM (lower strikes) and ITM (higher strikes)
        # For CALLs: Start at ATM, work towards OTM (higher strikes) and ITM (lower strikes)
        # Set violating marks to nil
        #
        # Returns a new array with enforced monotonicity
        #
        # @param options [Array] Array of option objects (must respond to :mark, :mark=, :strike, :underlying_price)
        # @param contract_type [String] 'CALL' or 'PUT'
        # @param method [String] 'adjust' or 'remove' (default: 'adjust')
        # @return [Array] New array with enforced monotonicity
        def self.enforce(options, contract_type:, method: 'adjust')
          new(contract_type: contract_type, method: method).enforce(options)
        end

        MAX_ITERATIONS = 100
        MIN_PRICE = 0.025
        CLOSE_THRESHOLD = 0.05 # 5% threshold to consider prices "close"

        def initialize(contract_type:, method: 'adjust')
          @contract_type = contract_type
          @is_call = contract_type == 'CALL'
          @method = method
          validate_method!
        end

        def enforce(options)
          # Create a copy of the options array to avoid modifying the original
          # Use clone instead of dup to preserve singleton methods (e.g., dynamic features)
          working_options = options.map(&:clone).sort_by { |o| o.strike }

          case @method
          when 'adjust'
            enforce_with_adjustment(working_options)
          when 'remove'
            enforce_with_removal(working_options)
          end
        end

        private

        def validate_method!
          unless ['adjust', 'remove'].include?(@method)
            raise ArgumentError, "Invalid method '#{@method}'. Must be 'adjust' or 'remove'"
          end
        end

        def enforce_with_adjustment(working_options)
          iteration = 0

          loop do
            violations = find_violations(working_options)
            break if violations.empty?

            iteration += 1
            break if iteration > MAX_ITERATIONS

            # Fix each violation individually using the enhanced strategy
            fix_individual_violations(working_options, violations)
          end

          working_options
        end

        def enforce_with_removal(working_options)
          # Validate that options have underlying_price
          validate_underlying_price!(working_options)

          # Find ATM strike
          atm_index = find_atm_index(working_options)

          if @is_call
            # For CALLS:
            # ATM → OTM (higher strikes): prices should decrease
            remove_violations_direction(working_options, atm_index, :forward, :otm)
            # ATM → ITM (lower strikes): prices should increase
            remove_violations_direction(working_options, atm_index, :backward, :itm)
          else
            # For PUTS:
            # ATM → OTM (lower strikes): prices should decrease
            remove_violations_direction(working_options, atm_index, :backward, :otm)
            # ATM → ITM (higher strikes): prices should increase
            remove_violations_direction(working_options, atm_index, :forward, :itm)
          end

          working_options
        end

        def validate_underlying_price!(options)
          return if options.empty?

          first_option = options.first
          unless first_option.respond_to?(:underlying_price) && first_option.underlying_price
            raise MissingUnderlyingPriceError, "Options must have underlying_price set for 'remove' method"
          end
        end

        def find_atm_index(options)
          underlying_price = options.first.underlying_price

          # Find the strike closest to underlying price
          atm_index = options.each_with_index.min_by do |option, _index|
            (option.strike - underlying_price).abs
          end.last

          atm_index
        end

        def remove_violations_direction(options, start_index, direction, moneyness_type)
          if direction == :forward
            # Move from start_index towards higher indices (higher strikes for calls, higher strikes for puts)
            (start_index...(options.length - 1)).each do |i|
              check_and_remove_violation(options[i], options[i + 1], moneyness_type)
            end
          else
            # Move from start_index towards lower indices (lower strikes for calls, lower strikes for puts)
            start_index.downto(1).each do |i|
              check_and_remove_violation(options[i], options[i - 1], moneyness_type)
            end
          end
        end

        def check_and_remove_violation(current_option, next_option, moneyness_type)
          return unless current_option.mark && next_option.mark

          if moneyness_type == :otm
            # Moving towards OTM: prices should decrease
            # Violation: next price >= current price
            if next_option.mark >= current_option.mark
              next_option.mark = nil
            end
          else
            # Moving towards ITM: prices should increase
            # Violation: next price <= current price
            if next_option.mark <= current_option.mark
              next_option.mark = nil
            end
          end
        end

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

        # Fix violations individually using enhanced strategy
        def fix_individual_violations(options, violations)
          violations.each do |idx|
            fix_single_violation(options, idx)
          end
        end

        # Enhanced strategy to fix a single violation at index idx
        # The violation is between options[idx] and options[idx+1]
        def fix_single_violation(options, idx)
          option = options[idx]
          next_option = options[idx + 1]
          prev_option = idx > 0 ? options[idx - 1] : nil

          # Strategy 1: Check if violation is close to neighbors - copy neighbor price
          if close_to_neighbors?(option, prev_option, next_option)
            fix_with_neighbor_copy(option, prev_option, next_option)
            return
          end

          # Strategy 2: Try alternative prices (open, high, low)
          if try_alternative_prices(option, prev_option, next_option)
            return
          end

          # Strategy 3: Try OHLC average
          if try_ohlc_average(option, prev_option, next_option)
            return
          end

          # Strategy 4: Last resort - use midpoint between neighbors
          fix_with_midpoint(option, prev_option, next_option)
        end

        # Check if the current price is close to neighbors (within threshold)
        def close_to_neighbors?(option, prev_option, next_option)
          return false unless prev_option && next_option

          # Calculate the spread between neighbors
          spread = (prev_option.mark - next_option.mark).abs
          return false if spread < MIN_PRICE

          # Check if current price is within threshold of either neighbor
          diff_from_prev = (option.mark - prev_option.mark).abs
          diff_from_next = (option.mark - next_option.mark).abs

          (diff_from_prev / spread) < CLOSE_THRESHOLD || (diff_from_next / spread) < CLOSE_THRESHOLD
        end

        # Copy the price of the closest neighbor
        def fix_with_neighbor_copy(option, prev_option, next_option)
          if prev_option && next_option
            diff_from_prev = (option.mark - prev_option.mark).abs
            diff_from_next = (option.mark - next_option.mark).abs

            # Copy the closer neighbor's price, with small adjustment for monotonicity
            if diff_from_prev < diff_from_next
              option.mark = calculate_valid_price(prev_option.mark, next_option.mark)
            else
              option.mark = calculate_valid_price(next_option.mark, prev_option.mark, reverse: true)
            end
          elsif prev_option
            option.mark = calculate_valid_price(prev_option.mark, nil)
          elsif next_option
            option.mark = calculate_valid_price(nil, next_option.mark)
          end
        end

        # Try alternative prices from the option (open, high, low)
        def try_alternative_prices(option, prev_option, next_option)
          candidates = []

          # Add alternative prices if available
          candidates << option.open if option.open && option.open > 0
          candidates << option.high if option.high && option.high > 0
          candidates << option.low if option.low && option.low > 0
          candidates << option.close if option.close && option.close > 0

          # Try each candidate price
          candidates.each do |candidate_price|
            if price_satisfies_monotonicity?(candidate_price, prev_option, next_option)
              option.mark = candidate_price
              return true
            end
          end

          false
        end

        # Try averaging OHLC prices
        def try_ohlc_average(option, prev_option, next_option)
          prices = []

          prices << option.open if option.open && option.open > 0
          prices << option.high if option.high && option.high > 0
          prices << option.low if option.low && option.low > 0
          prices << option.close if option.close && option.close > 0
          prices << option.mark if option.mark && option.mark > 0

          return false if prices.empty?

          avg_price = prices.sum / prices.size.to_f

          if price_satisfies_monotonicity?(avg_price, prev_option, next_option)
            option.mark = avg_price
            return true
          end

          false
        end

        # Last resort: use midpoint between neighbors
        def fix_with_midpoint(option, prev_option, next_option)
          if prev_option && next_option
            option.mark = (prev_option.mark + next_option.mark) / 2.0
          elsif prev_option
            # Only previous option available
            option.mark = @is_call ? [prev_option.mark - MIN_PRICE, MIN_PRICE].max : prev_option.mark + MIN_PRICE
          elsif next_option
            # Only next option available
            option.mark = @is_call ? next_option.mark + MIN_PRICE : [next_option.mark - MIN_PRICE, MIN_PRICE].max
          else
            # No neighbors - set minimum price
            option.mark = MIN_PRICE
          end
        end

        # Check if a candidate price satisfies monotonicity constraints
        def price_satisfies_monotonicity?(price, prev_option, next_option)
          satisfies_prev = true
          satisfies_next = true

          if prev_option
            satisfies_prev = @is_call ? price < prev_option.mark : price > prev_option.mark
          end

          if next_option
            satisfies_next = @is_call ? price > next_option.mark : price < next_option.mark
          end

          satisfies_prev && satisfies_next
        end

        # Calculate a valid price given neighbors, ensuring monotonicity
        def calculate_valid_price(reference_price, boundary_price, reverse: false)
          if reference_price && boundary_price
            # Return midpoint between reference and boundary
            (reference_price + boundary_price) / 2.0
          elsif reference_price
            # Only reference price available
            if @is_call
              reverse ? reference_price + MIN_PRICE : [reference_price - MIN_PRICE, MIN_PRICE].max
            else
              reverse ? [reference_price - MIN_PRICE, MIN_PRICE].max : reference_price + MIN_PRICE
            end
          elsif boundary_price
            # Only boundary price available
            if @is_call
              reverse ? [boundary_price - MIN_PRICE, MIN_PRICE].max : boundary_price + MIN_PRICE
            else
              reverse ? boundary_price + MIN_PRICE : [boundary_price - MIN_PRICE, MIN_PRICE].max
            end
          else
            MIN_PRICE
          end
        end
      end
    end
  end
end
