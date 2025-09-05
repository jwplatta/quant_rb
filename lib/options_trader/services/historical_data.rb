module OptionsTrader
  module Services
    class HistoricalData
      def initialize(provider: nil)
        @provider = provider
      end

      def get_price_history(symbol, **kwargs)
        @provider.get_price_history(symbol, **kwargs)
      end
    end
  end
end
