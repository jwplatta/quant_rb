require_relative "trade"

module Services
  module Trades
    class CallOption < Trade
      class << self
        def from_h(hash)
          expiration_date = hash[:expiration_date] ? Date.parse(hash[:expiration_date]) : nil
          CallOption.new(
            hash[:symbol],
            strike: hash[:strike],
            expiration_date: expiration_date,
            quantity: hash.fetch(:quantity, nil),
          ).tap do |call_option|
            call_option.open_credit_debit = hash.fetch(:open_credit_debit, nil)
            call_option.open_date = hash.fetch(:open_date, nil)
            call_option.open_fees = hash.fetch(:open_fees, nil)
            call_option.open_commission = hash.fetch(:open_commission, nil)
          end
        end

        def from_quote(quote)
          expiration_date = Date.new(
            quote.expiration_year,
            quote.expiration_month,
            quote.expiration_day
          )
          CallOption.new(
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
        @strategy = "SINGLE"
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
          "GREEN"
        elsif delta.abs < 0.28
          "YELLOW"
        else
          "RED"
        end
      end

      def tested?
        risk_status == "YELLOW"
      end

      def danger?
        risk_status == "RED"
      end

      def credit_debit
        nearest_increment(mark.round(2))
      end

      def net_credit_debit
        credit_debit * 100 - open_fees - open_commission
      end

      def short?
        quantity < 0
      end

      def long?
        quantity > 0
      end

      def quantity=(new_quantity)
        @quantity = new_quantity
      end

      def instruction
        if quantity < 0
          "SELL_TO_OPEN"
        elsif quantity > 0
          "BUY_TO_CLOSE"
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
          type: "CALL",
          symbol: symbol,
          strike: strike,
          quantity: quantity,
          expiration_date: expiration_date,
        }
      end
    end
  end
end
