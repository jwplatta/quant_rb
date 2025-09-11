  module OptionsTrader
    module Services
      class HistoricalOptionsChainSnapshot
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
          # Use the current snapshot's price data
          # create_quote_from_snapshot(symbol, @current_snapshot)
          # @current_snapshot[:quote].call
          strike_price = kwargs[:strike_price]
          spot_price = @underlying_price
          generate_quote(strike_price, spot_price)
        end

        # Duck typing - same interface as Services::Markets
        def get_option_chain(symbol, **kwargs)
          # Use the snapshot's lazy option chain
          # @current_snapshot[:option_chain].call(**kwargs)
          generate_options_chain
        end

        private

        def generate_options_chain
          return @options_chain unless @options_chain.nil?
          puts = []
          calls = []
          strike_range.each do |strike|
          end

          @options_chain = OptionsTrader::DataObjects::OptionChain.new
          @options_chain
        end

        def generate_quote
          generate_options_chain if @options_chain.nil?

          # TODO:
          OptionsTrader::DataObjects::Quote.new
        end
      end
    end
  end
