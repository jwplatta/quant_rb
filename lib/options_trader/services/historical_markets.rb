module OptionsTrader
  module Services
    class HistoricalMarkets
      def initialize(provider: nil)
        @provider = provider
      end

      def get_price_history_everyday(symbol, **kwargs)
      end

      def get_price_history_every_min(symbol, **kwargs)
        @provider.get_price_history(symbol, **kwargs)
      end

      def get_price_history_every_five_min
        @provider.get_price_history(symbol, **kwargs.merge)
      end

      def get_price_history_every_ten_min
        @provider.get_price_history(symbol, **kwargs.merge)
      end

      def get_price_history(symbol, **kwargs)
        @provider.get_price_history(symbol, **kwargs)
      end
    end
  end
end
