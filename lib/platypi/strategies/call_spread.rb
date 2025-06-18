# frozen_string_literal: true

module Platypi
  class CallSpread < StrategyBase
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
      short_leg.expiration_date
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

    def marks
      [short_leg.mark, long_leg.mark]
    end

    def market_change?
      short_leg.market_change? || long_leg.market_change?
    end

    def check_market
      threads = []
      threads << Thread.new { short_leg.check_market }
      threads << Thread.new { long_leg.check_market }
      threads.each(&:join)
    end

    def instruments
      [
        {
          symbol: short_leg.symbol,
          long_short: 'SHORT',
          put_call: 'CALL'
        },
        {
          symbol: long_leg.symbol,
          long_short: 'LONG',
          put_call: 'CALL'
        }
      ]
    end

    # def to_event(event_name, preview: false)
    #   {
    #     trade_id: trade_id,
    #     trade_event: event_name,  # OPEN, CLOSE
    #     trade_type: type, # e.g., CALL_SPREAD, PUT_SPREAD
    #     underlying_symbol: underlying_symbol,
    #     order_id: preview ? order_preview_id : order_id,
    #     order_instruction: preview ? order_preview_instruction : order_instruction,
    #     price: preview ? order_preview_price : order_price,
    #     fees: preview ? order_preview_fees : order_fees,
    #     commission: preview ? order_preview_commission : order_commission,
    #     expiration_date: expiration_date,
    #     quantity: quantity,
    #     instruments: instruments,
    #     timestamp: Time.now.utc
    #   }
    # end

    def to_s
      "<#{self.class.name} #{expiration_date}, " \
        "#{short_leg.symbol}, #{short_leg.strike}, " \
        "#{long_leg.symbol}, #{long_leg.strike}>"
    end
  end
end
