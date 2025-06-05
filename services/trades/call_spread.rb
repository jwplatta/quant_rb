# frozen_string_literal: true

require_relative 'trade'
require_relative 'call_option'

module Services
  module Trades
    class CallSpread < Trade
      attr_reader :short_leg, :long_leg

      def initialize(
        short_leg: nil,
        long_leg: nil,
        increment: 0.01,
        round: 2,
        quantity: 1
      )
        super(increment: increment, round: round, quantity: quantity)
        @short_leg = short_leg
        @long_leg = long_leg
      end

      def expiration_date
        @expiration_date ||= short_leg.expiration_date
      end

      def risk_status
        @short_leg.risk_status
      end

      def delta
        short_leg.delta
      end

      def credit_debit
        nearest_increment(short_leg.mark - long_leg.mark).round(2)
      end

      def credit_debit_raw
        short_leg.mark - long_leg.mark
      end

      def spread_width
        @spread_width ||= (long_leg.strike - short_leg.strike).abs
      end

      def symbols
        [short_leg.symbol, long_leg.symbol]
      end

      def check_market
        short_leg.check_market
        long_leg.check_market
      end
    end
  end
end
