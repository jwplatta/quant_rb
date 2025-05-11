# frozen_string_literal: true

require_relative 'trade'

module Services
  module Trades
    class PutOption < Trade
      class << self
        def from_h(hash)
          expiration_date = hash[:expiration_date] ? Date.parse(hash[:expiration_date]) : nil
          PutOption.new(
            hash[:symbol],
            strike: hash[:strike],
            expiration_date: expiration_date,
            quantity: hash.fetch(:quantity, nil)
          ).tap do |put_option|
            # Set the filled values
            put_option.instance_variable_set(:@filled_open_credit_debit,
                                             hash.fetch(:filled_open_credit_debit,
                                                        nil) || hash.fetch(:open_credit_debit, nil))
            put_option.instance_variable_set(:@filled_open_date,
                                             hash.fetch(:filled_open_date, nil) || hash.fetch(:open_date, nil))
            put_option.instance_variable_set(:@filled_open_fees,
                                             hash.fetch(:filled_open_fees, nil) || hash.fetch(:open_fees, nil))
            put_option.instance_variable_set(:@filled_open_commission,
                                             hash.fetch(:filled_open_commission,
                                                        nil) || hash.fetch(:open_commission, nil))
          end
        end

        def from_quote(quote)
          expiration_date = Date.new(
            quote.expiration_year,
            quote.expiration_month,
            quote.expiration_day
          )
          PutOption.new(
            quote.symbol,
            strike: quote.strike_price,
            delta: quote.delta,
            mark: quote.mark,
            ask: quote.ask_price,
            bid: quote.bid_price,
            expiration_date: expiration_date
          )
        end
      end

      attr_reader :symbol, :strike, :delta, :mark, :ask, :bid, :expiration_date

      def initialize(
        symbol, strike: nil, delta: 999, mark: nil, ask: nil, bid: nil,
        expiration_date: nil, quantity: nil, increment: 0.01, round: 2
      )
        super(
          increment: increment,
          round: round,
          quantity: quantity
        )
        @strategy = 'SINGLE'
        @symbol = symbol
        @strike = strike
        @delta = delta.abs
        @mark = mark
        @ask = ask
        @bid = bid
        @expiration_date = expiration_date
      end

      def risk_status
        if delta.abs < 0.16
          'GREEN'
        elsif delta.abs < 0.26
          'YELLOW'
        else
          'RED'
        end
      end

      def tested?
        risk_status == 'YELLOW'
      end

      def danger?
        risk_status == 'RED'
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

      ##################
      ### Schwab API ###
      ##################

      def check_market
        # NOTE: from schwab mixin
        quote(symbol).then do |q|
          @delta = q.delta.abs
          @mark = q.mark
          @ask = q.ask_price
          @bid = q.bid_price
          @strike = q.strike_price
          @expiration_date = Date.new(
            q.expiration_year,
            q.expiration_month,
            q.expiration_day
          )
        end
      end

      def to_h
        {
          type: 'PUT',
          symbol: symbol,
          strike: strike,
          quantity: quantity,
          expiration_date: expiration_date
        }
      end
    end
  end
end
