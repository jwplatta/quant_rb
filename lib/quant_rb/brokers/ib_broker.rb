# frozen_string_literal: true

module QuantRb
  module Brokers
    # Live/paper trading broker adapter using the ib-api gem (Interactive Brokers).
    #
    # TODO (Phase 7): Implement full IB combo order translation.
    #                 Reference: https://ib-ruby.github.io/ib-doc/
    #
    class IbBroker
      include BrokerAdapter

      attr_reader :host, :port, :client_id

      def initialize(host: "127.0.0.1", port: 7497, client_id: 1)
        @host = host
        @port = port
        @client_id = client_id
      end

      def submit_order(_order)
        raise NotImplementedError, "IbBroker is a Phase 7 stub — live order submission is not implemented yet"
      end

      def cancel_order(_ticket_id, reason: nil)
        raise NotImplementedError, "IbBroker is a Phase 7 stub — live order cancellation is not implemented yet"
      end

      def process_pending_orders(_slice, _portfolio)
        raise NotImplementedError, "IbBroker is a Phase 7 stub — live order processing is not implemented yet"
      end

      def get_quotes(_symbols)
        raise NotImplementedError, "IbBroker is a Phase 7 stub — quote retrieval is not implemented yet"
      end
    end
  end
end
