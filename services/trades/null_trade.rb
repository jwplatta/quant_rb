# frozen_string_literal: true

module Services
  module Trades
    class NullTrade
      def type
        :nulltrade
      end

      def symbol
        nil
      end

      def expiration_date
        nil
      end

      def call_spread
        nil
      end

      def put_spread
        nil
      end

      def credit_debit
        nil
      end

      def delta
        nil
      end
    end
  end
end
