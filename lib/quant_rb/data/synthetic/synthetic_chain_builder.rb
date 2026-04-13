# frozen_string_literal: true

module QuantRb
  module Data
    module Synthetic
      # Generates a synthetic OptionsChain from candle data when no real samples are available.
      # Based on the algorithm in doc/generate_option_chain.rb.
      #
      # Inputs:
      #   - SPX, VIX, VIX9D, VIX1D minute candles (CandleSeries objects)
      #   - target_time: the simulation Time to generate the chain for
      #   - expiration_date: the target expiry Date
      #
      # Output: DataObjects::OptionsChain with Black-Scholes prices and delta anchors
      #
      # TODO (Phase 5b): Port doc/generate_option_chain.rb logic here.
      #
      class SyntheticChainBuilder
        def initialize(spx_series:, vix_series:, vix9d_series: nil, vix1d_series: nil)
          @spx_series   = spx_series
          @vix_series   = vix_series
          @vix9d_series = vix9d_series
          @vix1d_series = vix1d_series
        end

        # Returns DataObjects::OptionsChain for the given target_time and expiration_date.
        def build(target_time:, expiration_date:, symbol: "SPXW")
          raise NotImplementedError, "SyntheticChainBuilder#build is a Phase 5b stub — not yet implemented. " \
                                     "See doc/generate_option_chain.rb for the reference algorithm."
        end
      end
    end
  end
end
