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

      def initialize(host: "127.0.0.1", port: 7497, client_id: 1)
        @host      = host
        @port      = port
        @client_id = client_id
        raise NotImplementedError, "IbBroker is a Phase 7 stub — not yet implemented"
      end
    end
  end
end
