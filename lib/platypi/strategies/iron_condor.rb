# frozen_string_literal: true

module Platypi
  # Iron condor option strategy
  class IronCondor < StrategyBase
    attr_reader :call_spread, :put_spread, :expiration_date, :underlying_symbol, :quantity

    def initialize(
      underlying_symbol:, call_spread:, put_spread:,
      expiration_date:, increment: 0.01, round: 2, quantity: 1
    )
      super(increment: increment, round: round)
      @put_spread = put_spread
      @call_spread = call_spread
      @underlying_symbol = underlying_symbol
      @expiration_date = expiration_date
      @quantity = quantity
    end

    def delta
      # Return the higher absolute delta between the two spreads
      if put_spread.delta.abs > call_spread.delta.abs
        put_spread.delta
      else
        call_spread.delta
      end
    end

    def credit
      nearest_increment(
        put_spread.credit + call_spread.credit
      )
    end

    def debit
      nearest_increment(
        put_spread.debit + call_spread.debit
      )
    end

    def symbols
      put_spread.symbols + call_spread.symbols
    end

    def strikes
      put_spread.strikes + call_spread.strikes
    end

    def marks
      put_spread.marks + call_spread.marks
    end

    def market_change?
      put_spread.market_change? || call_spread.market_change?
    end

    def spread_width
      put_spread.spread_width + call_spread.spread_width
    end

    def max_profit
      credit
    end

    def max_loss
      nearest_increment(spread_width - credit)
    end

    def check_market
      call_spread.check_market
      put_spread.check_market
    end

    def instruments
      put_spread.instruments + call_spread.instruments
    end

    def to_event(event_name, preview: false)
      {
        trade_id: trade_id,
        trade_event: event_name,  # OPEN, CLOSE
        trade_type: type, # iron_condor
        underlying_symbol: underlying_symbol,
        order_id: preview ? order_preview_id : order_id,
        order_instruction: preview ? order_preview_instruction : order_instruction,
        price: preview ? order_preview_price : order_price,
        fees: preview ? order_preview_fees : order_fees,
        commission: preview ? order_preview_commission : order_commission,
        expiration_date: expiration_date,
        quantity: quantity,
        instruments: instruments,
        timestamp: Time.now.utc
      }
    end

    def to_s
      "<#{self.class.name} #{expiration_date}, " \
        "PUT: #{put_spread.strikes.join('/')}, " \
        "CALL: #{call_spread.strikes.join('/')}, " \
        "Credit: #{credit}>"
    end
  end
end
