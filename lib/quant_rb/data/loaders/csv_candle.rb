# frozen_string_literal: true

require "csv"
require "time"

module QuantRb
  module Data
    module Loaders
      # Parses a single candle CSV file into an array of DataObjects::Candle.
      #
      # Expected CSV format (no header or header line starting with "datetime"):
      #   datetime,open,high,low,close,volume
      #   2019-12-27T14:30:00Z,3247.23,3247.64,3246.46,3247.61,0
      #
      # TODO (Phase 2): Implement full parsing with error handling and timezone support.
      #
      class CsvCandle
        def self.load(file_path)
          new(file_path).load
        end

        def initialize(file_path)
          @file_path = file_path
        end

        def load
          candles = []

          CSV.foreach(@file_path, headers: true) do |row|
            candles << build_candle(row)
          rescue StandardError => e
            warn "Warning: skipping malformed candle row in #{@file_path}: #{e.message}"
          end

          candles.compact
        end

        private

        def build_candle(row)
          QuantRb::DataObjects::Candle.new(
            datetime: Time.parse(row["datetime"] || row[0]),
            open:     row["open"]&.to_f   || row[1]&.to_f,
            high:     row["high"]&.to_f   || row[2]&.to_f,
            low:      row["low"]&.to_f    || row[3]&.to_f,
            close:    row["close"]&.to_f  || row[4]&.to_f,
            volume:   row["volume"]&.to_i || row[5]&.to_i || 0
          )
        end
      end
    end
  end
end
