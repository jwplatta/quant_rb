# frozen_string_literal: true

module QuantRb
  module Engine
    # Represents a single open position in the portfolio.
    #
    # TODO (Phase 3): Add mark-to-market, unrealized P&L, greeks aggregation.
    #
    Position = Struct.new(:order, :entry_price, :entry_time, keyword_init: true) do
      def pnl(current_price)
        (current_price - entry_price) * order.quantity
      end
    end
  end
end
