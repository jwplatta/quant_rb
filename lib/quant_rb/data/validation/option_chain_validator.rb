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

        Validation rules in this Stage 1 implementation:
        - An option mark should not be below intrinsic value.
        - Call marks should be non-increasing as strike increases.
        - Put marks should be non-decreasing as strike increases.
        - Bid should not exceed ask.

        Repair behavior:
        - Marks are lifted to intrinsic value when needed.
        - Extrinsic value is recomputed from repaired marks.
        - Monotonicity is enforced by clamping each option against its nearest prior strike.
        - Bid and ask are clamped back into a consistent relationship with the repaired mark.

        Shortcuts and limits:
        - This validator does not enforce put-call parity or a globally optimal arbitrage-free
          surface.
        - Repairs are local and greedy, not the result of a full optimization across the chain.
        - IV and greek consistency are expected to be handled by later stages after price repair.
      DOC
      class OptionChainValidator
        Violation = Struct.new(:type, :message, :option_symbol, keyword_init: true)

        def validate(chain)
          violations = []
          validate_side(chain.call_opts.sort_by(&:strike), :call, chain.underlying_price, violations)
          validate_side(chain.put_opts.sort_by(&:strike), :put, chain.underlying_price, violations)
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
          chain.all_options.each do |option|
            next unless option.bid && option.ask

            if option.bid > option.ask
              option.ask = option.bid
            end
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
            next if index.zero? || option.mark.nil? || options[index - 1].mark.nil?

            monotonic_ok = side == :call ? options[index - 1].mark >= option.mark : options[index - 1].mark <= option.mark
            next if monotonic_ok

            violations << Violation.new(type: :monotonicity, message: "strike monotonicity violation", option_symbol: option.symbol)
          end
        end

        def repair_side(options, side, spot)
          options.each_with_index do |option, index|
            intrinsic = Pricing::BlackScholes.intrinsic_value(spot: spot, strike: option.strike, contract_type: side == :call ? QuantRb::CALL : QuantRb::PUT)
            option.mark = [option.mark || intrinsic, intrinsic].max
            option.intrinsic = intrinsic
            option.extrinsic = [option.mark - intrinsic, 0.0].max
            option.bid = option.mark if option.bid.nil? || option.bid > option.mark
            option.ask = option.mark if option.ask.nil? || option.ask < option.mark
            next if index.zero?

            previous = options[index - 1]
            option.mark = [option.mark, previous.mark].min if side == :call
            option.mark = [option.mark, previous.mark].max if side == :put
            option.extrinsic = [option.mark - intrinsic, 0.0].max
            option.bid = [option.bid, option.mark].min
            option.ask = [option.ask, option.mark].max
          end
        end
      end
    end
  end
end
