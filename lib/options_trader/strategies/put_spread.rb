# frozen_string_literal: true

module OptionsTrader
  class PutSpread < StrategyBase
    class << self
      def from_json(json_string)
        data = JSON.parse(json_string, symbolize_names: true)
        from_h(data)
      end

      def from_h(data)
        short_leg = data[:short_leg] ? PutOption.from_h(data[:short_leg]) : nil
        long_leg = data[:long_leg] ? PutOption.from_h(data[:long_leg]) : nil

        new(
          underlying_symbol: data[:underlying_symbol],
          short_leg: short_leg,
          long_leg: long_leg,
          increment: data[:increment] || 0.01,
          round: data[:round] || 2,
          quantity: data[:quantity] || 1
        )
      end
    end

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
      short_leg.delta.abs
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

    def to_h
      {
        type: type,
        quantity: quantity,
        underlying_symbol: underlying_symbol,
        round: round,
        increment: increment,
        short_leg: {
          symbol: short_leg.symbol,
          strike: short_leg.strike,
          delta: short_leg.delta,
          mark: short_leg.mark,
          ask: short_leg.ask,
          bid: short_leg.bid,
          expiration_date: short_leg.expiration_date,
          open_interest: short_leg.open_interest
        },
        long_leg: {
          symbol: long_leg.symbol,
          strike: long_leg.strike,
          delta: long_leg.delta,
          mark: long_leg.mark,
          ask: long_leg.ask,
          bid: long_leg.bid,
          expiration_date: long_leg.expiration_date,
          open_interest: long_leg.open_interest
        }
      }
    end

    def to_s
      "<#{self.class.name} #{expiration_date}, " \
        "#{short_leg.symbol}, #{short_leg.strike}, " \
        "#{long_leg.symbol}, #{long_leg.strike}>"
    end

    def to_json(*args)
      to_h.to_json(*args)
    end

    def extract_kwargs(order_instruction)
      {
        strategy_type: type,
        short_leg_symbol: short_leg.symbol,
        long_leg_symbol: long_leg.symbol,
        price: strategy_price(order_instruction),
        quantity: quantity
      }
    end
  end
end
