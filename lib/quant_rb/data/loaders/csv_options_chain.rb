# frozen_string_literal: true

require "csv"
require "date"

module QuantRb
  module Data
    module Loaders
      # Parses a single tickrake options chain CSV into a DataObjects::OptionsChain.
      #
      # Expected CSV format (with header row):
      #   contract_type,symbol,description,strike,expiration_date,mark,bid,bid_size,
      #   ask,ask_size,last,last_size,open_interest,total_volume,delta,gamma,theta,
      #   vega,rho,volatility,theoretical_volatility,theoretical_option_value,
      #   intrinsic_value,extrinsic_value,underlying_price
      #
      # File naming pattern: {SYMBOL}_exp{EXPIRY_DATE}_{SAMPLE_DATE}_{HH-MM-SS}.csv
      # Example: SPXW_exp2025-12-18_2025-12-18_13-50-58.csv
      #
      # TODO (Phase 2): Implement full parsing with error handling and validation.
      #
      class CsvOptionsChain
        COLUMNS = %w[
          contract_type symbol description strike expiration_date
          mark bid bid_size ask ask_size last last_size
          open_interest total_volume delta gamma theta vega rho
          volatility theoretical_volatility theoretical_option_value
          intrinsic_value extrinsic_value underlying_price
        ].freeze

        def self.load(file_path)
          new(file_path).load
        end

        def initialize(file_path)
          @file_path = file_path
        end

        def load
          calls = []
          puts_  = []
          underlying_price = nil

          CSV.foreach(@file_path, headers: true) do |row|
            option = build_option(row)
            next unless option

            underlying_price ||= option.underlying_price
            option.call? ? calls << option : puts_ << option
          rescue StandardError => e
            warn "Warning: skipping malformed option row in #{@file_path}: #{e.message}"
          end

          symbol = extract_symbol_from_path(@file_path)
          QuantRb::DataObjects::OptionsChain.new(
            symbol:           symbol,
            underlying_price: underlying_price,
            call_opts:        calls,
            put_opts:         puts_
          )
        end

        private

        def build_option(row)
          contract_type = row["contract_type"]&.upcase
          return nil unless %w[CALL PUT].include?(contract_type)

          expiration = parse_date(row["expiration_date"])
          return nil unless expiration

          QuantRb::DataObjects::Option.new(
            symbol:             row["symbol"]&.strip,
            underlying_symbol:  extract_underlying(row["symbol"]),
            strike:             parse_float(row["strike"]),
            put_call:           contract_type,
            underlying_price:   parse_float(row["underlying_price"]),
            expiration_date:    expiration,
            mark:               parse_float(row["mark"]),
            bid:                parse_float(row["bid"]),
            ask:                parse_float(row["ask"]),
            open_interest:      row["open_interest"]&.to_i || 0,
            total_volume:       row["total_volume"]&.to_i || 0,
            delta:              parse_float(row["delta"]),
            gamma:              parse_float(row["gamma"]),
            theta:              parse_float(row["theta"]),
            vega:               parse_float(row["vega"]),
            rho:                parse_float(row["rho"]),
            volatility:         parse_float(row["volatility"]),
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

        def extract_symbol_from_path(path)
          File.basename(path).split("_").first
        end

        def extract_underlying(option_symbol)
          # e.g. "SPXW  260202C02800000" -> "SPXW"
          option_symbol&.strip&.split(/\s+/)&.first
        end
      end
    end
  end
end
