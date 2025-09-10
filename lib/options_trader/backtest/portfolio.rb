module OptionsTrader
  module Backtest
    class Portfolio
      attr_reader :balance, :positions, :trade_history

      def initialize(initial_balance: 100_000)
        @balance = initial_balance
        @positions = []
        @trade_history = []
      end

      def update_balance(amount)
        @balance += amount
      end

      def add_position(position)
        @positions << position
      end

      def remove_position(position)
        @positions.delete(position)
      end

      def record_trade(trade)
        @trade_history << trade
      end

      def total_value(current_prices = {})
        total_positions_value = @positions.sum do |position|
          current_price = current_prices[position[:symbol]] || position[:entry_price]
          current_price * position[:quantity]
        end
        @balance + total_positions_value
      end
    end
  end
end
