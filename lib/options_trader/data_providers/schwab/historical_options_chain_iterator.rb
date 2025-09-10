module OptionsTrader
  module DataProviders
    module Schwab
      class HistoricalOptionsChainIterator
        include Enumerable

        def initialize(provider, historical_data)
          @provider = provider
          @historical_data = historical_data
        end

        def each
          return enum_for(:each) unless block_given?

          @historical_data.each do |candle|
            market_snapshot = {
              datetime: candle.datetime,
              underlying_price: candle.close,
              quote: ->(symbol = nil) {
                @provider.generate_quote(
                  symbol: symbol,
                  asset_type: asset_type
                )
              }
              option_chain: ->(pricing_model: 'CRR') {
                @provider.generate_option_chain(
                  underlying_price: candle.close,
                  current_datetime: candle.datetime,
                  pricing_model: pricing_model
                )
              }
            }
            yield market_snapshot
          end
        end
      end
    end
  end
end
