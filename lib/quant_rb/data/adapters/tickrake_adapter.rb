# frozen_string_literal: true

require "tickrake"
require "csv"

module QuantRb
  module Data
    module Adapters
      class TickrakeAdapter
        OptionSnapshotRef = Struct.new(
          :provider,
          :ticker,
          :option_root,
          :expiration_date,
          :sampled_at_utc,
          :file_path,
          keyword_init: true
        )

        def initialize(loader: nil, config_path: nil)
          @loader = loader || build_loader(config_path:)
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

        def option_data_available?(provider:, ticker:, option_root:, start_date:, end_date:)
          @loader.options_available?(
            provider: provider,
            ticker: ticker,
            option_root: option_root,
            start_date: start_date,
            end_date: end_date
          )
        end

        def option_data_availability(provider:, ticker:, option_root:, start_date:, end_date:)
          @loader.options_availability(
            provider: provider,
            ticker: ticker,
            option_root: option_root,
            start_date: start_date,
            end_date: end_date
          )
        end

        def option_snapshot_refs(provider:, ticker:, option_root:, resolution:, start_date:, end_date:)
          results = @loader.send(
            :scan_options,
            provider: provider,
            ticker: ticker,
            option_root: option_root,
            start_date: start_date,
            end_date: end_date
          )
          selected_results = @loader.send(
            :select_option_results,
            results,
            frequency: normalize_frequency(resolution),
            bucket_selector: :last
          )

          selected_results.map do |result|
            OptionSnapshotRef.new(
              provider: result.provider_name,
              ticker: result.ticker,
              option_root: result.root_symbol,
              expiration_date: Date.iso8601(result.expiration_date),
              sampled_at_utc: Time.iso8601(result.sample_datetime).utc,
              file_path: result.file_path
            )
          end
        end

        def load_option_snapshot_rows(snapshot_ref:, timezone: nil, include_metadata: true)
          tz = @loader.send(:resolve_tz, timezone)
          sampled_at_utc = snapshot_ref.sampled_at_utc
          sampled_at_tz = @loader.send(:apply_tz, sampled_at_utc, tz)

          Enumerator.new do |yielder|
            CSV.foreach(snapshot_ref.file_path, headers: true) do |row|
              parsed = @loader.send(:parse_option_row, row)
              parsed["sampled_at_utc"] = sampled_at_utc
              parsed["sampled_at_tz"] = sampled_at_tz
              yielder << with_metadata(
                parsed,
                include_metadata: include_metadata,
                metadata: {
                  "dataset_type" => "options",
                  "provider_name" => snapshot_ref.provider,
                  "ticker" => snapshot_ref.ticker,
                  "option_root" => snapshot_ref.option_root,
                  "source_path" => snapshot_ref.file_path,
                  "sampled_at_utc" => sampled_at_utc,
                  "sampled_at_tz" => sampled_at_tz,
                  "expiration_date" => snapshot_ref.expiration_date
                }
              )
            end
          end
        end

        private

        def build_loader(config_path: nil)
          return Tickrake::DataLoader.new if config_path.nil?

          Tickrake::DataLoader.new(config_path: config_path)
        end

        def normalize_frequency(resolution)
          QuantRb::Intervals::RESOLUTION_MAP.fetch(resolution, resolution.to_s)
        end

        def with_metadata(row, include_metadata:, metadata:)
          return row unless include_metadata

          row.merge("metadata" => metadata)
        end
      end
    end
  end
end
