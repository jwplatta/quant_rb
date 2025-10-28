module OptionsTrader
  module SyntheticData
    module Transform
      class MonotonicityViolationError < StandardError; end

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
        def self.enforce(options, underlying_price, method: 'remove')
          new(
            underlying_price: underlying_price,
            method: method
          ).enforce(options)
        end

        def initialize(underlying_price:, method: 'remove')
          @underlying_price = underlying_price
          @method = method
        end

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

        def check_monotonicity(options)
          if is_call?
            sorted_opts = options.sort_by(&:strike)
            compare_marks(sorted_opts)
          else
            sorted_opts = options.sort_by(&:strike).reverse
            compare_marks(sorted_opts)
          end
        end

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

        def fix_otm_calls(call_opts)
          otm_opts = call_opts
            .select { |opt| opt.strike > @underlying_price }
            .sort_by(&:strike)

          return [] if otm_opts.empty?
          return otm_opts if otm_opts.length == 1

          fix_extrinsic(otm_opts, :check_non_increase)
        end

        def fix_itm_calls(call_opts)
          itm_opts = call_opts
            .select { |opt| opt.strike <= @underlying_price }
            .sort_by(&:strike)

          return [] if itm_opts.empty?
          return itm_opts if itm_opts.length == 1

          fix_extrinsic(itm_opts, :check_non_decrease)
        end

        def fix_otm_puts(put_opts)
          otm_opts = put_opts
            .select { |opt| opt.strike < @underlying_price }
            .sort_by(&:strike)

          return [] if otm_opts.empty?
          return otm_opts if otm_opts.length == 1

          fix_extrinsic(otm_opts, :check_non_decrease)
        end

        def fix_itm_puts(put_opts)
          itm_opts = put_opts
            .select { |opt| opt.strike >= @underlying_price }
            .sort_by(&:strike)

          return [] if itm_opts.empty?
          return itm_opts if itm_opts.length == 1

          fix_extrinsic(itm_opts, :check_non_increase)
        end

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
