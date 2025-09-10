module OptionsTrader
  module Services
    class BacktestOptionsChainMarkets
      def initialize(provider:)
        @provider = provider
        @current_snapshot = nil
      end

      def get_quote(symbol, **kwargs)
        return nil unless @current_snapshot

        # Use the current snapshot's price data
        # create_quote_from_snapshot(symbol, @current_snapshot)
        @current_snapshot[:quote].call
      end

      # Duck typing - same interface as Services::Markets
      def get_option_chain(symbol, **kwargs)
        return nil unless @current_snapshot

        # Use the snapshot's lazy option chain
        @current_snapshot[:option_chain].call
      end

      # Set the current market snapshot directly
      def set_current_snapshot(snapshot)
        @current_snapshot = snapshot
      end
    end
  end
end
