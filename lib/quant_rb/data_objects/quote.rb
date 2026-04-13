# frozen_string_literal: true

module QuantRb
  module DataObjects
    class Quote
      def initialize(symbol:, open:, close:, high:, low:, volume:, valid_time:, asset_type: nil, **kwargs)
        @symbol     = symbol
        @open       = open
        @close      = close
        @high       = high
        @low        = low
        @volume     = volume
        @valid_time = valid_time
        @asset_type = asset_type
      end

      attr_reader :symbol, :open, :close, :high, :low, :volume, :valid_time, :asset_type

      def mark(method: :close)
        case method
        when :close, "close" then close
        when :open,  "open"  then open
        when :high,  "high"  then high
        when :low,   "low"   then low
        when :avg,   "avg"   then (open + close + high + low) / 4.0
        else close
        end
      end
    end
  end
end
