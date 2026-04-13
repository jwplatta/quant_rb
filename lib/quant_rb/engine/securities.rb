# frozen_string_literal: true

module QuantRb
  module Engine
    # Registry of subscribed securities. Provides securities[symbol].price access.
    #
    # TODO (Phase 3): Extend with candle history buffer for indicator calculations.
    #
    class Securities
      def initialize
        @registry = {}
      end

      def register(symbol_key, subscription)
        @registry[symbol_key] = SecurityEntry.new(symbol_key, subscription)
      end

      def [](symbol_key)
        @registry[symbol_key]
      end

      # Called by BacktestEngine to update prices on each time step.
      def update(symbol_key, candle)
        entry = @registry[symbol_key]
        entry&.update(candle)
      end

      class SecurityEntry
        attr_reader :symbol_key, :subscription, :price, :candles

        def initialize(symbol_key, subscription)
          @symbol_key   = symbol_key
          @subscription = subscription
          @price        = nil
          @candles      = []
        end

        def update(candle)
          @price = candle.close
          @candles << candle
        end
      end
    end
  end
end
