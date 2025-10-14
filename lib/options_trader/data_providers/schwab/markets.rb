require_relative 'base'

module OptionsTrader
  module DataProviders
    module Schwab
      class Markets < Base
        def get_quote(symbol)
          validate_symbol(symbol)

          handle_api_errors("get_quote") do
            client.get_quote(symbol, return_data_objects: true)
          end
        end

        def get_quotes(symbols)
          symbols.each { |symbol| validate_symbol(symbol) }

          handle_api_errors("get_quotes") do
            client.get_quotes(symbols, return_data_objects: true)
          end
        end

        def get_option_chain(
          symbol,
          contract_type: 'ALL',
          strike_range: 'OTM',
          from_date: nil,
          to_date: nil,
          days_to_expiration: nil
        )
          validate_symbol(symbol)

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

        def get_price_history(symbol, **kwargs)
          validate_symbol(symbol)

          kwargs = kwargs.merge({
            need_extended_hours_data: true,
            need_previous_close: false,
            return_data_objects: true
          })

          handle_api_errors("get_price_history") do
            client.get_price_history(symbol, **kwargs)
          end
        end

        def get_price_history_every_min(symbol:, start_datetime:, end_datetime:)
          kwargs = {
            start_datetime: start_datetime,
            end_datetime: end_datetime,
            period_type: SchwabRb::PriceHistory::PeriodTypes::DAY,
            period: SchwabRb::PriceHistory::Periods::ONE_DAY,
            frequency_type: SchwabRb::PriceHistory::FrequencyTypes::MINUTE,
            frequency: SchwabRb::PriceHistory::Frequencies::EVERY_MINUTE
          }

          get_price_history(symbol, **kwargs)
        end

        def get_price_history_every_five_min(symbol:, start_datetime:, end_datetime:)
          kwargs = {
            start_datetime: start_datetime,
            end_datetime: end_datetime,
            period_type: SchwabRb::PriceHistory::PeriodTypes::DAY,
            period: SchwabRb::PriceHistory::Periods::ONE_DAY,
            frequency_type: SchwabRb::PriceHistory::FrequencyTypes::MINUTE,
            frequency: SchwabRb::PriceHistory::Frequencies::EVERY_FIVE_MINUTES
          }

          get_price_history(symbol, **kwargs)
        end

        def get_price_history_every_ten_min(symbol:, start_datetime:, end_datetime:)
          kwargs = {
            start_datetime: start_datetime,
            end_datetime: end_datetime,
            period_type: SchwabRb::PriceHistory::PeriodTypes::DAY,
            period: SchwabRb::PriceHistory::Periods::ONE_DAY,
            frequency_type: SchwabRb::PriceHistory::FrequencyTypes::MINUTE,
            frequency: SchwabRb::PriceHistory::Frequencies::EVERY_TEN_MINUTES
          }

          get_price_history(symbol, **kwargs)
        end

        def get_price_history_every_fifteen_min(symbol:, start_datetime:, end_datetime:)
          kwargs = {
            start_datetime: start_datetime,
            end_datetime: end_datetime,
            period_type: SchwabRb::PriceHistory::PeriodTypes::DAY,
            period: SchwabRb::PriceHistory::Periods::ONE_DAY,
            frequency_type: SchwabRb::PriceHistory::FrequencyTypes::MINUTE,
            frequency: SchwabRb::PriceHistory::Frequencies::EVERY_FIFTEEN_MINUTES
          }

          get_price_history(symbol, **kwargs)
        end

        def get_price_history_every_thirty_min(symbol:, start_datetime:, end_datetime:)
          kwargs = {
            start_datetime: start_datetime,
            end_datetime: end_datetime,
            period_type: SchwabRb::PriceHistory::PeriodTypes::DAY,
            period: SchwabRb::PriceHistory::Periods::ONE_DAY,
            frequency_type: SchwabRb::PriceHistory::FrequencyTypes::MINUTE,
            frequency: SchwabRb::PriceHistory::Frequencies::EVERY_THIRTY_MINUTES
          }

          get_price_history(symbol, **kwargs)
        end

        def get_price_history_everyday(symbol:, start_datetime:, end_datetime:)
          kwargs = {
            start_datetime: start_datetime,
            end_datetime: end_datetime,
            period_type: SchwabRb::PriceHistory::PeriodTypes::YEAR,
            period: SchwabRb::PriceHistory::Periods::TWENTY_YEARS,
            frequency_type: SchwabRb::PriceHistory::FrequencyTypes::DAILY,
            frequency: SchwabRb::PriceHistory::Frequencies::EVERY_MINUTE
          }

          get_price_history(symbol, **kwargs)
        end
      end
    end
  end
end
