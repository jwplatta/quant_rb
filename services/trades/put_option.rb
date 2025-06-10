# frozen_string_literal: true

require_relative 'trade'

module Services
  module Trades
    class PutOption < Trade
      include Quoteable

      class << self
        def from_schwab_option(option, quantity: 1)
          PutOption.new(option.symbol, quantity: quantity).tap do |put_opt|
            put_opt.strike = option.strike
            put_opt.delta = option.delta
            put_opt.mark = option.mark
            put_opt.ask = option.ask
            put_opt.bid = option.bid
            put_opt.expiration_date = option.expiration_date
            put_opt.open_interest = option.open_interest
          end
        end
      end

      attr_reader :symbol
      attr_writer :quantity

      def initialize(symbol, quantity: nil, increment: 0.01, round: 2)
        super(
          increment: increment,
          round: round,
          quantity: quantity
        )
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
