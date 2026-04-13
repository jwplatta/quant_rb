# frozen_string_literal: true

require "date"

module QuantRb
  module Data
    module Index
      # In-memory index of all options chain CSV files under a root path.
      # Supports LOCF (last-observation-carried-forward) lookup by sampled_at time.
      #
      # File naming pattern: {SYMBOL}_exp{EXPIRY_DATE}_{SAMPLE_DATE}_{HH-MM-SS}.csv
      # Example: SPXW_exp2025-12-18_2025-12-18_13-50-58.csv
      #
      # TODO (Phase 2): Implement full index with lazy CSV loading, synthetic fallback hook.
      #
      class OptionsChainIndex
        # root_path: directory containing the chain CSV files
        # symbol:    e.g. "SPXW"
        def initialize(root_path:, symbol:)
          @root_path = root_path
          @symbol    = symbol
          @index     = {}     # { sampled_at (Time) => { expiry_date (Date) => file_path } }
          @cache     = {}     # { file_path => OptionsChain } — lazy loaded
          build_index!
        end

        # Returns Hash { expiry_date (Date) => OptionsChain } for the given target_time.
        # Uses LOCF: finds the latest sampled_at <= target_time for each expiry.
        # Returns empty hash if no data is available.
        def chains_at(target_time, expiry_filter: nil)
          return {} if @sorted_times.empty?

          sampled_at = locf_lookup(target_time)
          return {} unless sampled_at

          expiry_map = @index[sampled_at]
          result = {}

          expiry_map.each do |expiry, file_path|
            next if expiry_filter && !expiry_filter.call(expiry)
            result[expiry] = load_chain(file_path)
          end

          result
        end

        def available_dates
          @sorted_times.map { |t| t.to_date }.uniq.sort
        end

        def size
          @index.size
        end

        private

        # Parses filename to extract sampled_at and expiry_date.
        # Returns [sampled_at (Time), expiry_date (Date)] or nil if unparseable.
        def parse_filename(filename)
          # Pattern: SPXW_exp2025-12-18_2025-12-18_13-50-58.csv
          match = filename.match(/\A#{Regexp.escape(@symbol)}_exp(\d{4}-\d{2}-\d{2})_(\d{4}-\d{2}-\d{2})_(\d{2}-\d{2}-\d{2})\.csv\z/)
          return nil unless match

          expiry_date = Date.parse(match[1])
          sample_date = match[2]
          sample_time = match[3].gsub("-", ":")
          sampled_at  = Time.parse("#{sample_date}T#{sample_time}")

          [sampled_at, expiry_date]
        rescue Date::Error, ArgumentError
          nil
        end

        def build_index!
          return unless Dir.exist?(@root_path)

          Dir.glob(File.join(@root_path, "#{@symbol}_exp*.csv")).each do |file_path|
            filename = File.basename(file_path)
            parsed   = parse_filename(filename)
            next unless parsed

            sampled_at, expiry_date = parsed
            @index[sampled_at] ||= {}
            @index[sampled_at][expiry_date] = file_path
          end

          @sorted_times = @index.keys.sort
        end

        def locf_lookup(target_time)
          # Binary search for rightmost sampled_at <= target_time
          lo  = 0
          hi  = @sorted_times.size - 1
          res = nil

          while lo <= hi
            mid = (lo + hi) / 2
            if @sorted_times[mid] <= target_time
              res = @sorted_times[mid]
              lo  = mid + 1
            else
              hi  = mid - 1
            end
          end

          res
        end

        def load_chain(file_path)
          @cache[file_path] ||= QuantRb::Data::Loaders::CsvOptionsChain.load(file_path)
        end
      end
    end
  end
end
