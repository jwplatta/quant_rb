# frozen_string_literal: true

module QuantRb
  module DataObjects
    # Immutable OHLCV candle value object.
    class Candle
      attr_reader :datetime, :open, :high, :low, :close, :volume

      def initialize(datetime:, open:, high:, low:, close:, volume:)
        @datetime = datetime
        @open = open
        @high = high
        @low = low
        @close = close
        @volume = volume
        freeze
      end

      def to_h
        { datetime: datetime, open: open, high: high, low: low, close: close, volume: volume }
      end
    end
  end
end
