module OptionsTrader
  module Trades
    class TradeBuilder
      def initialize
        @config = {}
      end

      def with_strategy(strategy)
        @config[:strategy] = strategy
        self
      end

      def with_adjuster(adjuster)
        @config[:adjuster] = adjuster
      end

      def with_progress_tracker(tracker)
        @config[:progress_tracker] = tracker
        self
      end

      def preview_mode
        @config[:preview] = true
        self
      end

      def build
        Trade.new(**@config)
      end
    end
  end
end
