module OptionsTrader
  module Strategies
    class VerticalSpread
      def initialize(short_leg:, long_leg:, contact_type:)
        @short_leg = short_leg
        @long_leg = long_leg
        @contact_type = contact_type
      end

      attr_reader :short_leg, :long_leg, :contact_type

      def delta
        @short_leg.delta.abs
      end

      def strikes
        [short_leg.strike, long_leg.strike]
      end

      def symbols
        [short_leg.symbol, long_leg.symbol]
      end
    end
  end
end