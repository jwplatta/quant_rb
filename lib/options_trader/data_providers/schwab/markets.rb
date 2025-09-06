module OptionsTrader
  module DataProviders
    module Schwab
      class Markets
        def client
          OptionsTrader::DataProviders::Schwab::Client.instance
        end

        def get_quote(symbol)
          client.get_quote(symbol, return_data_objects: true)
        end

        def get_quotes(symbols)
          client.get_quotes(symbols, return_data_objects: true)
        end

        def get_option_chain(symbol, contract_type: 'ALL',
          strike_range: 'OTM',
          from_date: nil,
          to_date: nil,
          days_to_expiration: nil
        )
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
end
