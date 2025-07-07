module Platypi
  module Trades
    class RiskMonitor
      attr_reader :green_delta, :yellow_delta

      def initialize(green_delta: 0.16, yellow_delta: 0.26)
        @green_delta = green_delta
        @yellow_delta = yellow_delta
      end

      def tested?(strategy)
        risk_status(strategy) == 'YELLOW'
      end

      def danger?(strategy)
        risk_status(strategy) == 'RED'
      end

      def risk_status(strategy)
        strategy.check_market # NOTE: ref quoteable.rb

        # Check if delta is nil first, then check if it responds to undefined? and is undefined
        if strategy.delta.nil? || (strategy.delta.respond_to?(:undefined?) && strategy.delta.undefined?)
          'UNKNOWN'
        elsif strategy.delta.abs < green_delta
          'GREEN'
        elsif strategy.delta.abs < yellow_delta
          'YELLOW'
        else
          'RED'
        end
      end

      def to_h
        {
          green_delta: green_delta,
          yellow_delta: yellow_delta
        }
      end

      def from_h(data)
        @green_delta = data[:green_delta] if data[:green_delta]
        @yellow_delta = data[:yellow_delta] if data[:yellow_delta]
      end
    end
  end
end
