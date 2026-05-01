# frozen_string_literal: true

module QuantRb
  module Brokers
    # Simulates order execution for backtesting using injected reality models.
    #
    # Fills are attempted on every call to #process_pending_orders (once per time step).
    # Limit orders fill if simulated fill price satisfies the limit condition.
    # Market orders always fill at the simulated price.
    #
    # TODO (Phase 3): Add order expiry, partial fill handling, and logging.
    #
    class BacktestBroker
      include BrokerAdapter

      def initialize(
        fill_model: QuantRb::Reality::BidAskFillModel.new,
        slippage_model: QuantRb::Reality::NullSlippageModel.new,
        transaction_fee_model: QuantRb::Reality::ZeroTransactionFeeModel.new
      )
        @fill_model = fill_model
        @slippage_model = slippage_model
        @transaction_fee_model = transaction_fee_model
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

      def cancel_all_pending_orders(reason: nil)
        cancelled = @pending_orders.map do |order|
          QuantRb::Engine::OrderTicket.new(order_id: order.id, status: :cancelled)
        end
        @pending_orders.clear
        cancelled
      end

      def process_pending_orders(slice, portfolio)
        portfolio.mark_to_market(slice)
        filled = []

        @pending_orders.each do |order|
          raw_fill_price = @fill_model.simulate_fill(order, slice)
          next unless raw_fill_price

          fill_price = @slippage_model.adjust_price(raw_fill_price, order: order, slice: slice).round(4)
          next unless fill_price

          if fillable?(order, fill_price)
            transaction_costs = @transaction_fee_model.estimate(order, fill_price: fill_price, slice: slice)
            portfolio.record_fill(order, fill_price, slice.time, transaction_costs: transaction_costs)
            filled << order
          end
        end

        @pending_orders -= filled
      end

      def process_expirations(slice, portfolio, strategy_class: nil)
        portfolio.process_expirations(slice, strategy_class: strategy_class)
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
