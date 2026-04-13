# frozen_string_literal: true

module QuantRb
  module Engine
    # Data snapshot passed to Strategy#on_data on each time step.
    #
    # slice.bars[:SPY]              -> DataObjects::Candle (or nil)
    # slice.option_chains[:SPXW_options]  -> Hash { Date => DataObjects::OptionsChain }
    # slice.time                    -> Time
    #
    class Slice
      attr_reader :time, :bars, :option_chains

      # bars:          Hash { symbol_key => DataObjects::Candle }
      # option_chains: Hash { symbol_key => Hash { Date => DataObjects::OptionsChain } }
      def initialize(time:, bars: {}, option_chains: {})
        @time          = time
        @bars          = bars.freeze
        @option_chains = option_chains.freeze
      end

      def empty?
        bars.empty? && option_chains.empty?
      end

      def [](key)
        bars[key] || option_chains[key]
      end
    end
  end
end
