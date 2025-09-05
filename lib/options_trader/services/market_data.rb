module OptionsTrader
  module Services
    class MarketData
      def initialize(provider: nil)
        @provider = provider
      end

      def get_option_chain(symbol, **kwargs)
        @provider.get_option_chain(symbol, **kwargs)
      end

      def get_quote(symbol, **kwargs)
        @provider.get_quote(symbol, **kwargs)
      end

      def get_quotes(symbols, **kwargs)
        @provider.get_quotes(symbols, **kwargs)
      end
    end
  end
end
