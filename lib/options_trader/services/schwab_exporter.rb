require 'csv'
require 'date'
require 'fileutils'

module OptionsTrader
  module Services
    class SchwabExporter
      include OptionsTrader::Loggable

      class << self
        def export(symbol:, start_date:, end_date:, interval:, output_dir:)
          new(
            symbol: symbol,
            start_date: start_date,
            end_date: end_date,
            interval: interval,
            output_dir: output_dir
          ).export
        end
      end

      def initialize(symbol:, start_date:, end_date:, interval:, output_dir:)
        @symbol = symbol
        @start_date = start_date
        @end_date = end_date
        @interval = interval
        @output_dir = output_dir
      end

      attr_reader :symbol, :start_date, :end_date, :interval, :output_dir

      def export
        if daily?
          daily_export
        else
          inter_daily_export
        end
      end

      def daily_export
        # Daily: HISTORICAL_FLATFILES_PATH/daily/year/symbol.csv
        folder_path = File.join(output_dir, interval, start_date.year.to_s)
        csv_file_path = File.join(folder_path, "#{symbol}.csv")

        if File.exist?(csv_file_path)
          logger.info("File already exists, skipping: #{csv_file_path}")
          return
        end

        fetch_start = DateTime.new(start_date.year, 1, 1, 0, 0, 0)
        fetch_end = DateTime.new(start_date.year, 12, 31, 23, 59, 59)

        begin
          price_history = historical_service.get_price_history_by_interval(
            symbol: symbol,
            start_datetime: fetch_start,
            end_datetime: fetch_end,
            interval: interval
          )
        rescue => e
          logger.error("Error fetching price history: #{e.message}")
          false
        end

        return if price_history.candles.empty?

        FileUtils.mkdir_p(folder_path) if !Dir.exist?(folder_path)

        write_candles_to_csv(csv_file_path, price_history.candles)

        logger.info("Successfully exported #{price_history.candles.length} candles to #{csv_file_path}")
      end

      def inter_daily_export
        if start_date == end_date
          export_single_date(start_date)
        else
          export_date_range
        end
      end

      private


      def export_date_range
        total_candles = 0
        processed_dates = []
        failed_dates = []

        (start_date..end_date).each do |current_date|
          next if current_date.wday == 0 || current_date.wday == 6
          export_single_date(current_date)
        end
      end

      def export_single_date(date)
        logger.info("Exporting data for #{symbol} on #{date} at #{interval} interval...")

        date_folder_path = File.join(
          output_dir,
          interval,
          date.year.to_s,
          "%02d" % date.month,
          "%02d" % date.day
        )

        date_csv_file_path = File.join(date_folder_path, "#{symbol}.csv")
        FileUtils.mkdir_p(date_folder_path)

        if File.exist?(date_csv_file_path)
          logger.info("File already exists, skipping: #{date_csv_file_path}")
          return
        end

        day_start = Time.new(date.year, date.month, date.day, 16, 0, 0, '-04:00').to_datetime
        day_end = Time.new(date.year, date.month, date.day, 9, 30, 0, '-04:00').to_datetime

        begin
          logger.info("Fetching price history for #{symbol} from #{day_start} to #{day_end}")
          price_history = historical_service.get_price_history_by_interval(
            symbol: symbol,
            start_datetime: day_start,
            end_datetime: day_end,
            interval: interval
          )

          if price_history && price_history.candles && !price_history.candles.empty?
            write_candles_to_csv(date_csv_file_path, price_history.candles)
            logger.info("Exported #{price_history.candles.length} candles to #{date_csv_file_path}")
          else
            logger.info("No data returned for #{symbol} on #{date}")
          end
        rescue => e
          logger.error("Error fetching price history for #{date}: #{e.message}")
        end
      end

      def daily?
        interval == OptionsTrader::Intervals::DAILY
      end

      def write_candles_to_csv(file_path, candles)
        CSV.open(file_path, 'w') do |csv|
          csv << ['symbol', 'datetime_ms', 'datetime_str', 'open', 'close', 'high', 'low', 'volume']

          candles.each do |candle|
            datetime_ms = candle.datetime.to_i * 1000
            datetime_str = candle.datetime.strftime('%Y-%m-%d %H:%M:%S')

            csv << [
              symbol,
              datetime_ms,
              datetime_str,
              candle.open,
              candle.close,
              candle.high,
              candle.low,
              candle.volume
            ]
          end
        end
      end

      def schwab_provider
        @schwab_provider ||= OptionsTrader::DataProviders::Schwab::Markets.new
      end

      def historical_service
        @historical_service ||= OptionsTrader::Services::HistoricalMarkets.new(provider: schwab_provider)
      end
    end
  end
end
