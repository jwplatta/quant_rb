# frozen_string_literal: true

module QuantRb
  module Engine
    # Future paper/live trading engine entry point.
    #
    # This intentionally exposes the expected construction and `.run` API now so
    # strategy code can target the same engine surface as backtests. The actual
    # event loop, market data adapters, and broker lifecycle are deferred.
    class LiveEngine
      attr_reader :strategy_class, :broker, :data_feed, :clock

      def self.run(strategy_class, broker:, data_feed: nil, clock: nil)
        new(
          strategy_class: strategy_class,
          broker: broker,
          data_feed: data_feed,
          clock: clock
        ).run
      end

      def initialize(strategy_class:, broker:, data_feed: nil, clock: nil)
        @strategy_class = strategy_class
        @broker = broker
        @data_feed = data_feed
        @clock = clock
      end

      def run
        raise NotImplementedError, "LiveEngine is a Phase 7 stub — paper/live execution is not implemented yet"
      end
    end
  end

  LiveEngine = Engine::LiveEngine
end
