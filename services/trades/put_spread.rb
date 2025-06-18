# frozen_string_literal: true

require_relative 'trade'
require_relative 'put_option'

module Services
  module Trades
    class PutSpread < Trade
      attr_reader :short_leg, :long_leg, :underlying_symbol, :quantity

      def initialize(
        underlying_symbol: nil,
        short_leg: nil,
        long_leg: nil,
        increment: 0.01,
        round: 2,
        quantity: 1
      )
        super(increment: increment, round: round)
        @underlying_symbol = underlying_symbol
        @quantity = quantity
        @short_leg = short_leg
        @long_leg = long_leg
      end

      def expiration_date
        @expiration_date ||= short_leg.expiration_date
      end

      def delta
        short_leg.delta
      end

      def credit
        nearest_increment(short_leg.mark - long_leg.mark)
      end

      def debit
        nearest_increment(long_leg.mark - short_leg.mark)
      end

      def spread_width
        @spread_width ||= (long_leg.strike - short_leg.strike).abs
      end

      def symbols
        [short_leg.symbol, long_leg.symbol]
      end

      def strikes
        [short_leg.strike, long_leg.strike]
      end

      def market_change?
        short_leg.market_change? || long_leg.market_change?
      end

      def marks
        [short_leg.mark, long_leg.mark]
      end

      def check_market
        threads = []
        threads << Thread.new { short_leg.check_market }
        threads << Thread.new { long_leg.check_market }
        threads.each(&:join)
      end

      def to_s
        "<#{self.class.name} #{expiration_date}, " \
          "#{short_leg.symbol}, #{short_leg.strike}, " \
          "#{long_leg.symbol}, #{long_leg.strike}>"
      end
    end
  end
end
