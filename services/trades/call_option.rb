# frozen_string_literal: true

require_relative 'trade'

module Services
  module Trades
    class CallOption < Trade
      include Quoteable

      class << self
        def from_schwab_option(option, quantity: 1)
          CallOption.new(option.symbol, quantity: quantity).tap do |call_opt|
            call_opt.strike = option.strike
            call_opt.delta = option.delta
            call_opt.mark = option.mark
            call_opt.ask = option.ask
            call_opt.bid = option.bid
            call_opt.expiration_date = option.expiration_date
            call_opt.open_interest = option.open_interest
          end
        end
      end

      attr_reader :symbol
      attr_writer :quantity

      def initialize(symbol, quantity: 1, increment: 0.01, round: 2)
        super(
          increment: increment,
          round: round,
        )
        @quantity = quantity
        @symbol = symbol
      end

      def credit
        nearest_increment(mark.round(2))
      end

      def debit
        nearest_increment(-mark.round(2))
      end

      def short?
        quantity.negative?
      end

      def long?
        quantity.positive?
      end
    end
  end
end
