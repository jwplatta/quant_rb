# frozen_string_literal: true

module QuantRb
  module Engine
    # Tracks cash, open positions, and trade history for a strategy run.
    #
    # TODO (Phase 3): Implement full position tracking, mark-to-market, drawdown.
    #
    class Portfolio
      attr_reader :cash, :positions, :trade_history

      def initialize(initial_cash:)
        @cash          = initial_cash.to_f
        @positions     = {}   # order_id => Position
        @trade_history = []   # Array of completed QuantRb::Reporting::TradeRecord
      end

      def invested?
        positions.any?
      end

      def total_value
        # TODO: add mark-to-market of open positions
        cash
      end

      # Called by broker after a fill is simulated.
      # credit_received: positive for credit orders (cash in), negative for debit orders.
      def record_fill(order, fill_price, fill_time)
        position = QuantRb::Engine::Position.new(
          order:       order,
          entry_price: fill_price,
          entry_time:  fill_time
        )
        @positions[order.id] = position
        @cash -= fill_price * order.quantity * 100 if order.multi_leg?
      end

      # Called when a position is closed.
      def close_position(order_id, close_price, close_time)
        position = @positions.delete(order_id)
        return unless position

        # TODO: build TradeRecord and push to trade_history
        @cash += close_price * position.order.quantity * 100 if position.order.multi_leg?
      end
    end
  end
end
