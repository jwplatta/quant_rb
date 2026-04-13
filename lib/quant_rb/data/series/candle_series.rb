# frozen_string_literal: true

module QuantRb
  module Data
    module Series
      # Sorted, immutable collection of Candle objects for a single symbol.
      class CandleSeries
        include Enumerable

        def initialize(candles = [])
          @candles = candles.sort_by(&:datetime).freeze
        end

        def each(&block)
          @candles.each(&block)
        end

        def size
          @candles.size
        end

        def [](index)
          @candles[index]
        end

        def empty?
          @candles.empty?
        end

        def to_a
          @candles.dup
        end

        # Returns the Candle with the largest datetime <= time (LOCF).
        # Returns nil if no candle exists at or before time.
        def at(time)
          # Binary search: find rightmost candle where datetime <= time
          idx = bsearch_right_leq(time)
          idx ? @candles[idx] : nil
        end

        # Returns all Candles with datetime in [start_time, end_time].
        def slice(start_time, end_time)
          @candles.select { |c| c.datetime >= start_time && c.datetime <= end_time }
        end

        # Returns the last n candles.
        def last(n = 1)
          @candles.last(n)
        end

        # Returns the first n candles.
        def first(n = 1)
          @candles.first(n)
        end

        private

        def bsearch_right_leq(time)
          lo  = 0
          hi  = @candles.size - 1
          res = nil

          while lo <= hi
            mid = (lo + hi) / 2
            if @candles[mid].datetime <= time
              res = mid
              lo  = mid + 1
            else
              hi  = mid - 1
            end
          end

          res
        end
      end

      # Loads candle CSVs from the configured data path and returns a CandleSeries.
      module CandleLoader
        def self.load(symbol:, resolution: :minute, data_path: nil, start_date: nil, end_date: nil)
          data_path ||= QuantRb::Data::DataSource.history_path
          file_path = resolve_file_path(symbol: symbol, resolution: resolution, data_path: data_path)

          candles = QuantRb::Data::Loaders::CsvCandle.load(file_path)

          if start_date || end_date
            candles = candles.select do |c|
              date = c.datetime.to_date
              (start_date.nil? || date >= start_date) && (end_date.nil? || date <= end_date)
            end
          end

          CandleSeries.new(candles)
        end

        def self.resolve_file_path(symbol:, resolution:, data_path:)
          interval = QuantRb::Intervals::RESOLUTION_MAP.fetch(resolution, resolution.to_s)
          upcased_symbol = symbol.upcase
          filename = "#{upcased_symbol}_#{interval}.csv"
          candidates = [
            File.join(data_path, upcased_symbol, filename),
            File.join(data_path, filename)
          ]

          candidates.find { |path| File.exist?(path) } || raise(ArgumentError, "Candle data not found: #{candidates.first}")
        end
      end
    end
  end
end
