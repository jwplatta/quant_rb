# frozen_string_literal: true

module OptionsTrader
  # Iron condor option strategy
  class IronCondor < StrategyBase
    class << self
      def from_json(json_string)
        data = JSON.parse(json_string, symbolize_names: true)
        from_h(data)
      end

      def from_h(data)
        put_spread = PutSpread.from_h(data[:put_spread])
        call_spread = CallSpread.from_h(data[:call_spread])

        expiration_date = data[:expiration_date]
        expiration_date = Date.parse(expiration_date) if expiration_date.is_a?(String)

        new(
          underlying_symbol: data[:underlying_symbol],
          call_spread: call_spread,
          put_spread: put_spread,
          increment: data[:increment] || 0.01,
          round: data[:round] || 2,
          quantity: data[:quantity] || 1
        )
      end
    end

    attr_reader :call_spread, :put_spread, :underlying_symbol, :quantity

    def initialize(
      underlying_symbol:, call_spread:, put_spread:,
      increment: 0.01, round: 2, quantity: 1
    )
      super(increment: increment, round: round)
      @put_spread = put_spread
      @call_spread = call_spread
      @underlying_symbol = underlying_symbol
      @quantity = quantity
    end

    def expiration_date
      @expiration_date ||= put_spread.expiration_date || call_spread.expiration_date
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

    def credit_delta_ratio
      total_delta = put_spread.delta.abs + call_spread.delta.abs
      return 0.0 if total_delta.zero?
      credit / total_delta
    end

    def to_s
      "<#{self.class.name} | #{expiration_date} | #{credit} | " \
        "PUTSPREAD #{put_spread.strikes.join('/')} | " \
        "CALLSPREAD #{call_spread.strikes.join('/')}>"
    end

    def to_h
      {
        type: type,
        quantity: quantity,
        underlying_symbol: underlying_symbol,
        round: round,
        increment: increment,
        put_spread: put_spread.to_h,
        call_spread: call_spread.to_h
      }
    end

    def to_json(*args)
      to_h.to_json(*args)
    end
  end
end
