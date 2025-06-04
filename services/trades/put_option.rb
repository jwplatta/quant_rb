# frozen_string_literal: true

require_relative 'trade'

module Services
  module Trades
    class PutOption < Trade
      class << self
        def from_schwab_option(option, quantity: 1)
          PutOption.new(
            option.symbol,
            strike: option.strike,
            delta: option.delta,
            mark: option.mark,
            ask: option.ask,
            bid: option.bid,
            expiration_date: option.expiration_date,
            open_interest: option.open_interest,
            quantity: quantity
          )
        end
      end

      attr_reader :symbol, :strike, :delta, :mark, :ask, :bid, :expiration_date

      def initialize(
        symbol, strike: nil, delta: 999, mark: nil, ask: nil, bid: nil,
        expiration_date: nil, quantity: nil, increment: 0.01, round: 2,
        open_interest: nil
      )
        super(
          increment: increment,
          round: round,
          quantity: quantity
        )
        @symbol = symbol
        @strike = strike
        @delta = delta.abs
        @mark = mark
        @ask = ask
        @bid = bid
        @expiration_date = expiration_date
        @open_interest = open_interest
      end

      def credit_debit
        nearest_increment(mark.round(2))
      end

      def net_credit_debit
        credit_debit * 100 - filled_open_fees.to_f - filled_open_commission.to_f
      end

      def short?
        quantity.negative?
      end

      def long?
        quantity.positive?
      end

      attr_writer :quantity

      def instruction
        if quantity.negative?
          'SELL_TO_OPEN'
        elsif quantity.positive?
          'BUY_TO_CLOSE'
        end
      end
    end
  end
end
