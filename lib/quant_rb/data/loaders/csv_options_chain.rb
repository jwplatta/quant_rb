# frozen_string_literal: true

require "csv"
require "date"
require "time"

module QuantRb
  module Data
    module Loaders
      # Parses a single tickrake options chain CSV into a DataObjects::OptionsChain.
      class CsvOptionsChain
        FILENAME_PATTERN = /\A(?<symbol>.+?)_exp(?<expiry>\d{4}-\d{2}-\d{2})_(?<sample_date>\d{4}-\d{2}-\d{2})_(?<sample_time>\d{2}-\d{2}-\d{2})\.csv\z/.freeze

        def self.load(file_path)
          new(file_path).load
        end

        def initialize(file_path)
          @file_path = file_path
        end

        def load
          metadata = parse_filename_metadata
          calls = []
          puts_  = []
          underlying_price = nil

          CSV.foreach(@file_path, headers: true) do |row|
            next if row.to_h.empty?

            option = build_option(row, metadata)
            next unless option

            underlying_price ||= option.underlying_price
            option.call? ? calls << option : puts_ << option
          rescue StandardError => e
            warn "Warning: skipping malformed option row in #{@file_path}: #{e.message}"
          end

          QuantRb::DataObjects::OptionsChain.new(
            symbol:           metadata[:symbol],
            underlying_price: underlying_price,
            call_opts:        calls,
            put_opts:         puts_
          )
        end

        private

        def build_option(row, metadata)
          contract_type = row["contract_type"]&.upcase
          return nil unless %w[CALL PUT].include?(contract_type)

          expiration = parse_date(row["expiration_date"])
          return nil unless expiration

          QuantRb::DataObjects::Option.new(
            symbol:             row["symbol"]&.strip,
            underlying_symbol:  extract_underlying(row["symbol"]) || metadata[:symbol],
            strike:             parse_float(row["strike"]),
            put_call:           contract_type,
            underlying_price:   parse_float(row["underlying_price"]),
            expiration_date:    expiration,
            days_to_expiration: metadata[:sampled_at] ? (expiration - metadata[:sampled_at].to_date).to_i : 0,
            mark:               parse_float(row["mark"]),
            bid:                parse_float(row["bid"]),
            ask:                parse_float(row["ask"]),
            open_interest:      parse_integer(row["open_interest"]) || 0,
            total_volume:       parse_integer(row["total_volume"]) || 0,
            delta:              parse_float(row["delta"]),
            gamma:              parse_float(row["gamma"]),
            theta:              parse_float(row["theta"]),
            vega:               parse_float(row["vega"]),
            rho:                parse_float(row["rho"]),
            volatility:         parse_float(row["volatility"]),
            timestamp:          metadata[:sampled_at],
            intrinsic:          parse_float(row["intrinsic_value"]),
            extrinsic:          parse_float(row["extrinsic_value"])
          )
        end

        def parse_float(val)
          return nil if val.nil? || val.to_s.strip.empty?
          val.to_f
        end

        def parse_date(val)
          return nil if val.nil? || val.to_s.strip.empty?

          Date.parse(val)
        rescue Date::Error
          nil
        end

        def parse_integer(val)
          return nil if val.nil? || val.to_s.strip.empty?

          Integer(val, 10)
        end

        def parse_filename_metadata
          filename = File.basename(@file_path)
          match = filename.match(FILENAME_PATTERN)
          raise ArgumentError, "Unrecognized options chain filename: #{filename}" unless match

          {
            symbol: match[:symbol],
            sampled_at: Time.parse("#{match[:sample_date]} #{match[:sample_time].tr('-', ':')}")
          }
        end

        def extract_underlying(option_symbol)
          option_symbol&.strip&.split(/\s+/)&.first
        end
      end
    end
  end
end
