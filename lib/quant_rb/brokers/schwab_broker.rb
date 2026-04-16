# frozen_string_literal: true

module QuantRb
  module Brokers
    # Live/paper trading broker adapter using the schwab_rb gem.
    #
    # TODO (Phase 7): Implement full Schwab order translation and lifecycle management.
    #                 Reference: bots/spx_1dte/order_manager.rb for the existing translation logic.
    #
    class SchwabBroker
      include BrokerAdapter

      attr_reader :account_name, :schwab_client

      def initialize(account_name:, schwab_client: nil)
        @account_name = account_name
        @schwab_client = schwab_client
      end

      def submit_order(_order)
        raise NotImplementedError, "SchwabBroker is a Phase 7 stub — live order submission is not implemented yet"
      end

      def cancel_order(_ticket_id, reason: nil)
        raise NotImplementedError, "SchwabBroker is a Phase 7 stub — live order cancellation is not implemented yet"
      end

      def process_pending_orders(_slice, _portfolio)
        raise NotImplementedError, "SchwabBroker is a Phase 7 stub — live order processing is not implemented yet"
      end

      def get_quotes(_symbols)
        raise NotImplementedError, "SchwabBroker is a Phase 7 stub — quote retrieval is not implemented yet"
      end
    end
  end
end
