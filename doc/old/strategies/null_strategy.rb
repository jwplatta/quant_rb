# frozen_string_literal: true

module OptionsTrader
  # Null trade strategy (represents no trade)
  class NullStrategy
    def type
      'nullstrategy'
    end

    def symbol
      nil
    end

    def expiration_date
      nil
    end

    def call_spread
      nil
    end

    def put_spread
      nil
    end

    def credit_debit
      nil
    end

    def delta
      nil
    end

    def to_h
      {
        type: type
      }
    end

    def nil?
      true
    end

    def to_json(*args)
      to_h.to_json(*args)
    end
  end
end
