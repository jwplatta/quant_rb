# frozen_string_literal: true

module OptionsTrader
  # Base class for all trading strategies
  class StrategyBase
    attr_accessor :increment, :round, :trade_id

    def initialize(increment: 0.01, round: 2)
      @increment = increment
      @round = round
    end

    def type
      self.class.name.split('::').last.downcase
    end

    def nearest_increment(value)
      ((value / increment).round * increment).round(round)
    end
  end
end
