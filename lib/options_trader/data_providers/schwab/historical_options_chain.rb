require_relative 'base'

module OptionsTrader
  module DataProviders
    module Schwab
      class HistoricalOptionsChain < Base
        def initialize(
          underlying_symbol:,
          start_datetime:,
          end_datetime:,
          interval: OptionsTrader::Intervals::FIVE_MIN,
          pricing_model: OptionsTrader::COX_ROSS_RUBINSTEIN,
          strike_step_size: 10
        )
          super()
          @underlying_symbol = underlying_symbol
          @start_datetime = start_datetime
          @end_datetime = end_datetime
          @interval = interval
          @underlying_price_history = fetch_underlying_price_history
          @pricing_model = pricing_model
          @strike_step_size = strike_step_size
        end

        def generate_option_quote(underlying_price:, current_datetime:, **kwargs)
          # NOTE: SchwabRb::DataObjects::QuotoFactory.build
        end

        def generate_option_chain(spot_price:, current_datetime:, **kwargs)
          # Uses Indicators::CoxRossRubinstein for option pricing
          # Returns Schwab API-compatible data structure
          # Single place for all option chain generation logic
          # strike_range
          # price =
        end

        def strike_range
          return @strike_range if defined?(@strike_range)

          spot_prices = @underlying_price_history.map { |candle| candle.close }
          avg_price = spot_prices.sum.to_f / spot_prices.size
          # TODO: parameterize the range size
          min_price = ((avg_price * 0.25) / 10).round * 10
          max_price = ((avg_price * 1.25) / 10).round * 10

          @strike_range = (min_price..max_price).step(@strike_step_size).to_a
          @strike_range
        end

        def backtest_iterator
          HistoricalOptionsChainIterator.new(self, @underlying_price_history)
        end

        def steps
          @steps ||= @underlying_price_history.map { |s| s.datetime }
        end

        private

        def fetch_underlying_price_history(symbol, start_datetime, end_datetime, interval)
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
      end
    end
  end
end
