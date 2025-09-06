module OptionsTrader
  module DataProviders
    class SyntheticMarket
      def client
        OptionsTrader::DataProviders::Schwab::Client.instance
      end

      def get_quote(symbol, **kwargs)
      end

      def get_quotes(symbols, **kwargs)
      end

      def get_option_chain
      end
    end
  end
end
