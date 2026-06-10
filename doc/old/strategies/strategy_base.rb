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

    def strategy_price(order_instruction)
      if order_instruction == :open
        credit
      elsif order_instruction == :exit
        debit.abs
      else
        raise "Unsupported order instruction: #{order_instruction}"
      end
    end

    def add_index(symbol, resolution: :minute)
      { symbol: symbol, resolution: resolution, kind: :index }
    end
  end
end
