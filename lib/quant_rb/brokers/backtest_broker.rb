# frozen_string_literal: true

module QuantRb
  module Brokers
    # Simulates order execution for backtesting using a FillModel.
    #
    # Fills are attempted on every call to #process_pending_orders (once per time step).
    # Limit orders fill if simulated fill price satisfies the limit condition.
    # Market orders always fill at the simulated price.
    #
    # TODO (Phase 3): Add order expiry, partial fill handling, and logging.
    #
    class BacktestBroker
      include BrokerAdapter

      def initialize(fill_model: nil, execution_cost_model: nil)
        @fill_model = fill_model || QuantRb::Engine::FillModel.new(model: :bid_ask)
        @execution_cost_model = execution_cost_model || QuantRb::Brokers::ExecutionCostModel.none
        @pending_orders = []
      end

      def submit_order(order)
        @pending_orders << order
        QuantRb::Engine::OrderTicket.new(order_id: order.id, status: :submitted)
      end

      def cancel_order(ticket_id, reason: nil)
        @pending_orders.reject! { |o| o.id == ticket_id }
        QuantRb::Engine::OrderTicket.new(order_id: ticket_id, status: :cancelled)
      end

      def process_pending_orders(slice, portfolio)
        portfolio.mark_to_market(slice)
        filled = []

        @pending_orders.each do |order|
          fill_price = @fill_model.simulate_fill(order, slice)
          next unless fill_price

          if fillable?(order, fill_price)
            transaction_costs = @execution_cost_model.estimate(order)
            portfolio.record_fill(order, fill_price, slice.time, transaction_costs: transaction_costs)
            filled << order
          end
        end

        @pending_orders -= filled
      end

      def get_quotes(_symbols)
        {}
      end

      def pending_orders
        @pending_orders.dup.freeze
      end

      private

      def fillable?(order, fill_price)
        return true if order.market_order?

        case order.direction
        when :credit then fill_price >= order.limit_price
        when :debit   then fill_price.abs <= order.limit_price
        when :buy     then true
        when :sell    then true
        else true
        end
      end
    end
  end
end
