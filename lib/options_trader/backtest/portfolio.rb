module OptionsTrader
  module Backtest
    class Portfolio
      attr_reader :balance, :trades, :trade_history

      def initialize(initial_balance: 100_000)
        @balance = initial_balance
        @trades = []
        @trade_history = []
      end

      def update_balance(amount)
        @balance += amount
      end

      def add_trade(trade)
        @trades << trade
      end

      def remove_trade(trade)
        @trades.delete(trade)
      end

      def update_balance(amount)
        @balance += amount
      end

      def add_trade(trade)
        @trades << trade
      end

      def remove_trade(trade)
        @trades.delete(trade)
      end

      def record_trade(trade)
        @trade_history << trade
      end

      def total_value(current_prices = {})
        total_trades_value = @trades.sum do |trade|
          current_price = current_prices[trade[:symbol]] || trade[:entry_price]
          current_price * trade[:quantity]
        end
        @balance + total_trades_value
      end
    end
  end
end
