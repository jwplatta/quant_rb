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

      def initialize(account_name:, schwab_client: nil)
        @account_name  = account_name
        @schwab_client = schwab_client
        raise NotImplementedError, "SchwabBroker is a Phase 7 stub — not yet implemented"
      end
    end
  end
end
