# frozen_string_literal: true

module QuantRb
  module Data
    module Adapters
      class TickrakeAdapter
        def initialize(loader: nil)
          @loader = loader || build_loader
        end

        def load_candle_series(provider:, ticker:, resolution:, start_date:, end_date:)
          frequency = normalize_frequency(resolution)
          candles = @loader.load_candles(
            provider: provider,
            ticker: ticker,
            frequency: frequency,
            start_date: start_date,
            end_date: end_date
          ).map do |row|
            QuantRb::DataObjects::Candle.new(
              datetime: row.fetch("datetime"),
              open: row.fetch("open"),
              high: row.fetch("high"),
              low: row.fetch("low"),
              close: row.fetch("close"),
              volume: row.fetch("volume", 0)
            )
          end

          QuantRb::Data::Series::CandleSeries.new(candles)
        end

        def load_option_chain_rows(provider:, ticker:, option_root:, resolution:, start_date:, end_date:, include_metadata: true)
          @loader.load_option_chains(
            provider: provider,
            ticker: ticker,
            option_root: option_root,
            start_date: start_date,
            end_date: end_date,
            frequency: normalize_frequency(resolution),
            include_metadata: include_metadata
          ).to_a
        end

        private

        def build_loader
          require_tickrake!
          Tickrake::DataLoader.new
        end

        def require_tickrake!
          require "tickrake"
        rescue LoadError
          local_tickrake = File.expand_path("../../../../../tickrake/lib/tickrake", __dir__)
          require local_tickrake if File.exist?("#{local_tickrake}.rb")
          return if defined?(Tickrake::DataLoader)

          raise
        end

        def normalize_frequency(resolution)
          QuantRb::Intervals::RESOLUTION_MAP.fetch(resolution, resolution.to_s)
        end
      end
    end
  end
end
