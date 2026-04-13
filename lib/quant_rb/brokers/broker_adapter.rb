# frozen_string_literal: true

module QuantRb
  module Brokers
    # Interface that all broker adapters must implement.
    module BrokerAdapter
      # Submit an order. Returns an OrderTicket.
      def submit_order(order)
        raise NotImplementedError, "#{self.class}#submit_order not implemented"
      end

      # Cancel a pending order by ticket id.
      def cancel_order(ticket_id, reason: nil)
        raise NotImplementedError, "#{self.class}#cancel_order not implemented"
      end

      # Process pending orders against current slice data. Called by BacktestEngine each step.
      def process_pending_orders(slice, portfolio)
        raise NotImplementedError, "#{self.class}#process_pending_orders not implemented"
      end

      # Returns current quote data for a list of symbols.
      def get_quotes(symbols)
        raise NotImplementedError, "#{self.class}#get_quotes not implemented"
      end
    end
  end
end
