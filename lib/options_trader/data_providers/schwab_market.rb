module OptionsTrader
  module DataProviders
    class SchwabMarket
      def client
        OptionsTrader::Schwab::Client.instance
      end

      def get_quote(symbol, **kwargs)
        client.get_quote(symbol, **kwargs)
      end

      def get_quotes(symbols, **kwargs)
        client.get_quotes(symbols, **kwargs)
      end

      def get_option_chain(symbol, **kwargs)
        kwargs = {
          contract_type: contract_type,
          strike_range: strike_range
        }

        if days_to_expiration
          kwargs[:days_to_expiration] = days_to_expiration
        else
          kwargs[:to_date] = to_date
          kwargs[:from_date] = from_date if from_date
        end

        client.get_option_chain(symbol, **kwargs)
      end
    end
  end
end
