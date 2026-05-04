# frozen_string_literal: true

module QuantRb
  module Data
    module Validation
      <<~DOC
        Validates and repairs a vanilla option chain using a small set of practical no-arbitrage
        constraints.

        Assumptions:
        - The chain contains plain-vanilla calls and puts sorted or sortable by strike.
        - The underlying spot used on each option is consistent with the chain-level spot.
        - The primary price field being validated is `mark`, with `bid` and `ask` treated as
          supporting quote fields.

        Validation rules in this implementation:
        - An option mark should not be below intrinsic value.
        - Call marks should not exceed spot; put marks should not exceed strike.
        - Call marks should be non-increasing as strike increases.
        - Put marks should be non-decreasing as strike increases.
        - Marks should be convex by strike on each side.
        - Calls and puts at the same strike should approximately respect put-call parity.
        - Bid should not exceed ask.

        Repair behavior:
        - Marks are lifted to intrinsic value when needed.
        - Extrinsic value is recomputed from repaired marks.
        - Monotonicity is enforced by clamping each option against its nearest prior strike.
        - Bid and ask are clamped back into a consistent relationship with the repaired mark.

        Shortcuts and limits:
        - This validator does not produce a globally optimal arbitrage-free surface.
        - Repairs are local and greedy, not the result of a full optimization across the chain.
        - IV and greek consistency are expected to be handled by later stages after price repair.
      DOC
      class OptionChainValidator
        PARITY_TOLERANCE = 0.25

        Violation = Struct.new(:type, :message, :option_symbol, keyword_init: true)

        def validate(chain)
          violations = []
          validate_side(chain.call_opts.sort_by(&:strike), :call, chain.underlying_price, violations)
          validate_side(chain.put_opts.sort_by(&:strike), :put, chain.underlying_price, violations)
          validate_parity(chain, violations)
          chain.all_options.each do |option|
            if option.bid && option.ask && option.bid > option.ask
              violations << Violation.new(type: :bid_ask, message: "bid exceeds ask", option_symbol: option.symbol)
            end
          end
          violations
        end

        def repair(chain)
          repair_side(chain.call_opts.sort_by(&:strike), :call, chain.underlying_price)
          repair_side(chain.put_opts.sort_by(&:strike), :put, chain.underlying_price)
          repair_parity(chain)
          repair_side(chain.call_opts.sort_by(&:strike), :call, chain.underlying_price)
          repair_side(chain.put_opts.sort_by(&:strike), :put, chain.underlying_price)
          chain.all_options.each do |option|
            next unless option.bid && option.ask

            requote_around_mark!(option) if option.bid > option.ask
          end
          chain
        end

        private

        def validate_side(options, side, spot, violations)
          options.each_with_index do |option, index|
            intrinsic = Pricing::BlackScholes.intrinsic_value(spot: spot, strike: option.strike, contract_type: side == :call ? QuantRb::CALL : QuantRb::PUT)
            if option.mark && option.mark < intrinsic
              violations << Violation.new(type: :intrinsic_floor, message: "mark below intrinsic", option_symbol: option.symbol)
            end
            upper_bound = option_upper_bound(option, side, spot)
            if option.mark && option.mark > upper_bound + 1e-6
              violations << Violation.new(type: :upper_bound, message: "mark above no-arbitrage upper bound", option_symbol: option.symbol)
            end
            next if index.zero? || option.mark.nil? || options[index - 1].mark.nil?

            monotonic_ok = side == :call ? options[index - 1].mark >= option.mark : options[index - 1].mark <= option.mark
            next if monotonic_ok

            violations << Violation.new(type: :monotonicity, message: "strike monotonicity violation", option_symbol: option.symbol)
          end

          options.each_cons(3) do |left, middle, right|
            next if [left.mark, middle.mark, right.mark].any?(&:nil?)

            upper_bound = linear_interpolation(left, middle.strike, right)
            next if middle.mark <= upper_bound + 1e-6

            violations << Violation.new(type: :convexity, message: "strike convexity violation", option_symbol: middle.symbol)
          end
        end

        def repair_side(options, side, spot)
          options.each_with_index do |option, index|
            intrinsic = Pricing::BlackScholes.intrinsic_value(spot: spot, strike: option.strike, contract_type: side == :call ? QuantRb::CALL : QuantRb::PUT)
            option.mark = [option.mark || intrinsic, intrinsic].max
            option.mark = [option.mark, option_upper_bound(option, side, spot)].min
            option.intrinsic = intrinsic
            option.extrinsic = [option.mark - intrinsic, 0.0].max
            requote_around_mark!(option)
            next if index.zero?

            previous = options[index - 1]
            option.mark = [option.mark, previous.mark].min if side == :call
            option.mark = [option.mark, previous.mark].max if side == :put
            option.extrinsic = [option.mark - intrinsic, 0.0].max
            requote_around_mark!(option)
          end

          options.each_cons(3) do |left, middle, right|
            next if [left.mark, middle.mark, right.mark].any?(&:nil?)

            upper_bound = linear_interpolation(left, middle.strike, right)
            next if middle.mark <= upper_bound

            middle.mark = upper_bound.round(4)
            intrinsic = Pricing::BlackScholes.intrinsic_value(
              spot: spot,
              strike: middle.strike,
              contract_type: side == :call ? QuantRb::CALL : QuantRb::PUT
            )
            middle.mark = [middle.mark, intrinsic].max
            middle.mark = [middle.mark, option_upper_bound(middle, side, spot)].min
            middle.intrinsic = intrinsic
            middle.extrinsic = [middle.mark - intrinsic, 0.0].max
            requote_around_mark!(middle)
          end
        end

        def validate_parity(chain, violations)
          paired_options(chain).each do |call_option, put_option|
            residual = parity_residual(call_option, put_option, chain.underlying_price)
            next if residual.abs <= PARITY_TOLERANCE

            violations << Violation.new(type: :put_call_parity, message: "put-call parity violation", option_symbol: call_option.symbol)
          end
        end

        def repair_parity(chain)
          paired_options(chain).each do |call_option, put_option|
            residual = parity_residual(call_option, put_option, chain.underlying_price)
            next if residual.abs <= PARITY_TOLERANCE

            adjustment = residual / 2.0
            call_intrinsic = Pricing::BlackScholes.intrinsic_value(
              spot: chain.underlying_price,
              strike: call_option.strike,
              contract_type: QuantRb::CALL
            )
            put_intrinsic = Pricing::BlackScholes.intrinsic_value(
              spot: chain.underlying_price,
              strike: put_option.strike,
              contract_type: QuantRb::PUT
            )

            call_option.mark = [call_option.mark - adjustment, call_intrinsic].max.round(4)
            put_option.mark = [put_option.mark + adjustment, put_intrinsic].max.round(4)
            call_option.mark = [call_option.mark, option_upper_bound(call_option, :call, chain.underlying_price)].min
            put_option.mark = [put_option.mark, option_upper_bound(put_option, :put, chain.underlying_price)].min
            call_option.intrinsic = call_intrinsic
            put_option.intrinsic = put_intrinsic
            call_option.extrinsic = [call_option.mark - call_intrinsic, 0.0].max
            put_option.extrinsic = [put_option.mark - put_intrinsic, 0.0].max
            requote_around_mark!(call_option)
            requote_around_mark!(put_option)
          end
        end

        def paired_options(chain)
          puts_by_strike = chain.put_opts.each_with_object({}) { |option, memo| memo[option.strike] = option }
          chain.call_opts.filter_map do |call_option|
            put_option = puts_by_strike[call_option.strike]
            next unless put_option && call_option.mark && put_option.mark

            [call_option, put_option]
          end
        end

        def parity_residual(call_option, put_option, spot)
          (call_option.mark - put_option.mark) - (spot - call_option.strike)
        end

        def linear_interpolation(left, strike, right)
          slope = (right.mark - left.mark) / (right.strike - left.strike).to_f
          left.mark + (slope * (strike - left.strike))
        end

        def option_upper_bound(option, side, spot)
          side == :call ? spot.to_f : option.strike.to_f
        end

        def requote_around_mark!(option)
          spread =
            if option.bid && option.ask
              [(option.ask - option.bid).abs, 0.05].max
            else
              [option.mark.to_f.abs * 0.02, 0.05].max
            end
          half_spread = spread / 2.0
          option.bid = [option.mark - half_spread, 0.0].max.round(4)
          option.ask = [option.mark + half_spread, option.bid].max.round(4)
        end
      end
    end
  end
end
