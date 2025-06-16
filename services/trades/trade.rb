# frozen_string_literal: true

require_relative '../../mixins/schwab/schwab'
require_relative '../../mixins/orderable'
require_relative '../../mixins/quoteable'
require_relative '../../mixins/position_progress'

module Services
  module Trades
    class Trade
      include Orderable
      include PositionProgress

      attr_accessor :increment, :round, :quantity

      def initialize(increment: 0.01, round: 2, quantity: 1)
        @increment = increment
        @round = round
        @quantity = quantity

        initialize_orderable
        init_progress
      end

      def type
        self.class.name.split('::').last.downcase.to_sym
      end

      def nearest_increment(value)
        ((value / increment).round * increment).round(round)
      end
    end
  end
end
