module OptionsTrader
  module Services
    class HistoricalMarkets
      def initialize(provider: nil)
        @provider = provider
      end

      def get_price_history_by_interval(symbol:, start_datetime:, end_datetime:, interval:)
        case interval
        when OptionsTrader::Intervals::ONE_MIN
          get_price_history_every_min(symbol: symbol, start_datetime: start_datetime, end_datetime: end_datetime)
        when OptionsTrader::Intervals::FIVE_MIN
          get_price_history_every_five_min(symbol: symbol, start_datetime: start_datetime, end_datetime: end_datetime)
        when OptionsTrader::Intervals::TEN_MIN
          get_price_history_every_ten_min(symbol: symbol, start_datetime: start_datetime, end_datetime: end_datetime)
        when OptionsTrader::Intervals::DAILY
          get_price_history_everyday(symbol: symbol, start_datetime: start_datetime, end_datetime: end_datetime)
        end
      end

      def get_price_history_everyday(symbol:, start_datetime:, end_datetime:)
        @provider.get_price_history_everyday(symbol: symbol, start_datetime: start_datetime, end_datetime: end_datetime)
      end

      def get_price_history_every_min(symbol:, start_datetime:, end_datetime:)
        @provider.get_price_history_every_min(symbol: symbol, start_datetime: start_datetime, end_datetime: end_datetime)
      end

      def get_price_history_every_five_min(symbol:, start_datetime:, end_datetime:)
        @provider.get_price_history_every_five_min(symbol: symbol, start_datetime: start_datetime, end_datetime: end_datetime)
      end

      def get_price_history_every_ten_min(symbol:, start_datetime:, end_datetime:)
        @provider.get_price_history_every_ten_min(symbol: symbol, start_datetime: start_datetime, end_datetime: end_datetime)
      end

      def get_price_history_every_fifteen_min(symbol:, start_datetime:, end_datetime:)
        @provider.get_price_history_every_fifteen_min(
          symbol: symbol, start_datetime: start_datetime, end_datetime: end_datetime
        )
      end

      def get_price_history_every_thirty_min(symbol:, start_datetime:, end_datetime:)
        @provider.get_price_history_every_thirty_min(
          symbol: symbol, start_datetime: start_datetime, end_datetime: end_datetime
        )
      end

      def get_price_history(symbol:, start_datetime:, end_datetime:)
        kwargs = {
          start_datetime: start_datetime,
          end_datetime: end_datetime
        }
        @provider.get_price_history(symbol, **kwargs)
      end
    end
  end
end
