# frozen_string_literal: true

require "date"
require "time"

module QuantRb
  module Data
    module Index
      # In-memory index of all options chain CSV files under a root path.
      # Supports LOCF (last-observation-carried-forward) lookup by sampled_at time.
      class OptionsChainIndex
        FILENAME_PATTERN = /\A(?<symbol>.+?)_exp(?<expiry>\d{4}-\d{2}-\d{2})_(?<sample_date>\d{4}-\d{2}-\d{2})_(?<sample_time>\d{2}-\d{2}-\d{2})\.csv\z/.freeze

        # root_path: directory containing the chain CSV files
        # symbol:    e.g. "SPXW"
        def initialize(root_path:, symbol:)
          @root_path = root_path
          @symbol    = symbol
          @index     = {}     # { sampled_at (Time) => { expiry_date (Date) => file_path } }
          @cache     = {}     # { file_path => OptionsChain } — lazy loaded
          @sorted_times = []
          build_index!
        end

        # Returns Hash { expiry_date (Date) => OptionsChain } for the given target_time.
        # Uses LOCF: finds the latest sampled_at <= target_time for each expiry.
        # Returns empty hash if no data is available.
        def chains_at(target_time, expiry_filter: nil)
          return {} if @sorted_times.empty?

          sampled_at = locf_lookup(target_time)
          return {} unless sampled_at

          result = {}
          @index.fetch(sampled_at, {}).each do |expiry, file_path|
            next unless matches_expiry_filter?(expiry, expiry_filter)

            result[expiry] = load_chain(file_path)
          end

          result
        end

        def available_dates
          @sorted_times.map { |t| t.to_date }.uniq.sort
        end

        def size
          @index.values.sum(&:size)
        end

        private

        def parse_filename(filename)
          match = filename.match(FILENAME_PATTERN)
          return nil unless match
          return nil unless match[:symbol] == @symbol

          expiry_date = Date.parse(match[:expiry])
          sample_date = match[:sample_date]
          sample_time = match[:sample_time].tr("-", ":")
          sampled_at = Time.parse("#{sample_date} #{sample_time}")

          [sampled_at, expiry_date]
        rescue Date::Error, ArgumentError
          nil
        end

        def build_index!
          raise ArgumentError, "Options chain root path not found: #{@root_path}" unless Dir.exist?(@root_path)

          Dir.glob(File.join(@root_path, "**", "#{@symbol}_exp*.csv")).sort.each do |file_path|
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

        def matches_expiry_filter?(expiry, expiry_filter)
          return true if expiry_filter.nil?
          return expiry_filter.call(expiry) if expiry_filter.respond_to?(:call)
          return expiry_filter.cover?(expiry) if expiry_filter.respond_to?(:cover?)
          return expiry_filter.include?(expiry) if expiry_filter.respond_to?(:include?)

          expiry == expiry_filter
        end
      end
    end
  end
end
