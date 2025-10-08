  module OptionsTrader
    module Services
      class HistoricalSnapshot
        def initialize(symbol:, spot_price:, datetime:, pricing_model:, strike_range: [])
          @symbol = symbol
          @spot_price = spot_price
          @datetime = datetime
          @pricing_model = pricing_model
          @strike_range = strike_range
          # NOTE: we will need the strike range and average spot price to generate the options chain
          @options_chain = nil
        end

        def get_quote(symbol, **kwargs)
          strike_price = kwargs[:strike_price]
          generate_quote(strike_price)
        end

        # Duck typing - same interface as Services::Markets
        def get_option_chain(symbol, **kwargs)
          # Use the snapshot's lazy option chain
          # @current_snapshot[:option_chain].call(**kwargs)
          generate_options_chain
        end

        private

        def generate_options_chain
        end
      end
    end
  end
