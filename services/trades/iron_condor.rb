# frozen_string_literal: true

require_relative 'trade'

module Services
  module Trades
    class IronCondor
      attr_reader :call_spread, :put_spread, :expiration_date

      def initialize(call_spread:, put_spread:, expiration_date:, increment: 0.01, round: 2, quantity: 1)
        super(increment: increment, round: round, quantity: quantity)
        @put_spread = put_spread
        @call_spread = call_spread
        @expiration_date = expiration_date
      end

      def delta
        if put_spread.delta > call_spread.delta
          put_spread.delta
        else
          call_spread.delta
        end
      end

      def credit
        credit_debit
      end

      def debit
        credit_debit
      end

      def credit_debit
        nearest_increment(
          put_spread.credit_debit_raw + call_spread.credit_debit_raw
        )
      end

      def credit_debit_raw
        put_spread.credit_debit_raw + call_spread.credit_debit_raw
      end

      def expected_return
        ((credit_debit * prob_of_profit) - (max_loss * (1 - prob_of_profit)))
      end

      def symbols
        put_spread.symbols + call_spread.symbols
      end

      def check_market
        call_spread.check_market
        put_spread.check_market
      end
    end
  end
end
