# frozen_string_literal: true

require "csv"
require "time"

module QuantRb
  module Data
    module Loaders
      # Parses a single candle CSV file into an array of DataObjects::Candle.
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
            next if row.to_h.empty?

            candles << build_candle(row)
          rescue StandardError => e
            QuantRb.logger.warn("Skipping malformed candle row in #{@file_path}: #{e.message}")
          end

          candles.compact.sort_by(&:datetime)
        end

        private

        def build_candle(row)
          QuantRb::DataObjects::Candle.new(
            datetime: parse_time(value_from(row, "datetime", 0)),
            open: parse_float(value_from(row, "open", 1)),
            high: parse_float(value_from(row, "high", 2)),
            low: parse_float(value_from(row, "low", 3)),
            close: parse_float(value_from(row, "close", 4)),
            volume: parse_integer(value_from(row, "volume", 5)) || 0
          )
        end

        def value_from(row, header, index)
          row[header] || row[index]
        end

        def parse_time(value)
          Time.iso8601(value.to_s)
        end

        def parse_float(value)
          return nil if value.nil? || value.to_s.strip.empty?

          Float(value)
        end

        def parse_integer(value)
          return nil if value.nil? || value.to_s.strip.empty?

          Integer(value, 10)
        end
      end
    end
  end
end
