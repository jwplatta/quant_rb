# frozen_string_literal: true

module Platypi
  # Put option strategy
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

    def to_event(event_name, preview: false)
      {
        trade_id: trade_id,
        trade_event: event_name,  # OPEN, CLOSE
        trade_type: type, # e.g., CALL_OPTION, PUT_OPTION
        underlying_symbol: symbol.split(/\d/)[0], # Extract underlying from option symbol
        order_id: preview ? order_preview_id : order_id,
        order_instruction: preview ? order_preview_instruction : order_instruction,
        price: preview ? order_preview_price : order_price,
        fees: preview ? order_preview_fees : order_fees,
        commission: preview ? order_preview_commission : order_commission,
        expiration_date: expiration_date,
        quantity: quantity,
        instruments: [{
          symbol: symbol,
          long_short: quantity.positive? ? 'LONG' : 'SHORT',
          put_call: 'PUT'
        }],
        timestamp: Time.now.utc
      }
    end
  end
end
