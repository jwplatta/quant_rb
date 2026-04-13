# frozen_string_literal: true

module QuantRb
  module DataObjects
    # Immutable OHLCV candle value object.
    Candle = Struct.new(:datetime, :open, :high, :low, :close, :volume, keyword_init: true) do
      def to_h
        { datetime: datetime, open: open, high: high, low: low, close: close, volume: volume }
      end
    end
  end
end
