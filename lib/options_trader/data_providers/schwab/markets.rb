require_relative 'base'

module OptionsTrader
  module DataProviders
    module Schwab
      class Markets < Base
        def get_quote(symbol)
          validate_symbol(symbol)
          log_operation(:info, "Fetching quote for symbol: #{symbol}")
          
          handle_api_errors("get_quote") do
            client.get_quote(symbol, return_data_objects: true)
          end
        end

        def get_quotes(symbols)
          symbols.each { |symbol| validate_symbol(symbol) }
          log_operation(:info, "Fetching quotes for symbols: #{symbols.join(', ')}")

          handle_api_errors("get_quotes") do
            client.get_quotes(symbols, return_data_objects: true)
          end
        end

        def get_option_chain(symbol, contract_type: 'ALL',
          strike_range: 'OTM',
          from_date: nil,
          to_date: nil,
          days_to_expiration: nil
        )
          validate_symbol(symbol)
          log_operation(:info, "Fetching option chain for symbol: #{symbol} with contract_type: #{contract_type}, strike_range: #{strike_range}, from_date: #{from_date}, to_date: #{to_date}, days_to_expiration: #{days_to_expiration}")

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

          handle_api_errors("get_option_chain") do
            client.get_option_chain(symbol, **kwargs)
          end
        end
      end
    end
  end
end
