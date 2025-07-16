# frozen_string_literal: true

module OptionsTrader
  class PutOption < StrategyBase
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

      def from_json(json_string)
        data = JSON.parse(json_string, symbolize_names: true)
        from_hash(data)
      end

      def from_h(data)
        new(data[:symbol],
            quantity: data[:quantity] || 1,
            increment: data[:increment] || 0.01,
            round: data[:round] || 2).tap do |option|
          option.strike = data[:strike]
          option.delta = data[:delta]
          option.mark = data[:mark]
          option.ask = data[:ask]
          option.bid = data[:bid]

          # Handle date conversion - it might be a string from JSON
          expiration_date = data[:expiration_date]
          option.expiration_date = expiration_date.is_a?(String) ? Date.parse(expiration_date) : expiration_date

          option.open_interest = data[:open_interest]
        end
      end
    end

    attr_reader :symbol, :quantity

    def initialize(symbol, quantity: 1, increment: 0.01, round: 2)
      super(
        increment: increment,
        round: round
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

    def to_h
      {
        type: type,
        symbol: symbol,
        quantity: quantity,
        round: round,
        increment: increment,
        strike: strike,
        delta: delta,
        mark: mark,
        ask: ask,
        bid: bid,
        expiration_date: expiration_date,
        open_interest: open_interest
      }
    end

    def to_json(*args)
      to_h.to_json(*args)
    end
  end
end
