# frozen_string_literal: true

module QuantRb
  module Data
    module Validation
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
