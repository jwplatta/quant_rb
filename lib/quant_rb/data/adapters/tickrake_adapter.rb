# frozen_string_literal: true

require "tickrake"

module QuantRb
  module Data
    module Adapters
      class TickrakeAdapter
        def initialize(loader: nil)
          @loader = loader || build_loader
        end

        def load_candle_series(provider:, ticker:, resolution:, start_date:, end_date:, timezone: nil)
          frequency = normalize_frequency(resolution)
          candles = @loader.load_candles(
            provider: provider,
            ticker: ticker,
            frequency: frequency,
            start_date: start_date,
            end_date: end_date,
            timezone: timezone
          ).map do |row|
            QuantRb::DataObjects::Candle.new(
              datetime: row["datetime_tz"] || row["datetime_utc"] || row.fetch("datetime"),
              open: row.fetch("open"),
              high: row.fetch("high"),
              low: row.fetch("low"),
              close: row.fetch("close"),
              volume: row.fetch("volume", 0)
            )
          end

          QuantRb::Data::Series::CandleSeries.new(candles)
        end

        def load_option_chain_rows(provider:, ticker:, option_root:, resolution:, start_date:, end_date:, timezone: nil, include_metadata: true)
          @loader.load_option_chains(
            provider: provider,
            ticker: ticker,
            option_root: option_root,
            start_date: start_date,
            end_date: end_date,
            frequency: normalize_frequency(resolution),
            timezone: timezone,
            include_metadata: include_metadata,
            order: :sample_time_asc
          )
        end

        private

        def build_loader
          Tickrake::DataLoader.new
        end

        def normalize_frequency(resolution)
          QuantRb::Intervals::RESOLUTION_MAP.fetch(resolution, resolution.to_s)
        end
      end
    end
  end
end
