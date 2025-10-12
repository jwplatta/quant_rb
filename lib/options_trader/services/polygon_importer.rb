require 'csv'
require 'date'

module OptionsTrader
  module Services
    class PolygonImporter
      include OptionsTrader::Loggable

      BASE_DATA_PATH = '/Volumes/ext_docs/options_trader/polygon/minute_aggs_v1'
      BATCH_SIZE = 500

      def initialize(root_symbol:, underlying_symbol:, year: nil, month: nil, day: nil)
        @root_symbol = root_symbol
        @underlying_symbol = underlying_symbol
        @year = year
        @month = month
        @day = day
        @imported_count = 0
        @skipped_count = 0
        @error_count = 0
        @batch = []
      end

      def import!
        logger.info("Starting import for #{@root_symbol} (underlying: #{@underlying_symbol})")

        validate_data_path!

        if specific_date_requested?
          import_specific_date
        else
          import_all_available_data
        end

        flush_batch
        log_import_summary
      end

      private

      def validate_data_path!
        unless Dir.exist?(BASE_DATA_PATH)
          raise "Data path does not exist: #{BASE_DATA_PATH}"
        end
      end

      def specific_date_requested?
        @year && @month && @day
      end

      def import_specific_date
        date_path = File.join(BASE_DATA_PATH, @year.to_s, sprintf('%02d', @month), sprintf('%02d', @day))
        csv_file = File.join(date_path, "#{@root_symbol}.csv")

        if File.exist?(csv_file)
          import_csv_file(csv_file, Date.new(@year, @month, @day))
        else
          logger.warn("CSV file not found: #{csv_file}")
        end
      end

      def import_all_available_data
        year_dirs = Dir.glob(File.join(BASE_DATA_PATH, '*')).select { |d| File.directory?(d) }

        year_dirs.sort.each do |year_dir|
          year = File.basename(year_dir).to_i
          month_dirs = Dir.glob(File.join(year_dir, '*')).select { |d| File.directory?(d) }

          month_dirs.sort.each do |month_dir|
            month = File.basename(month_dir).to_i
            day_dirs = Dir.glob(File.join(month_dir, '*')).select { |d| File.directory?(d) }

            day_dirs.sort.each do |day_dir|
              day = File.basename(day_dir).to_i
              csv_file = File.join(day_dir, "#{@root_symbol}.csv")

              if File.exist?(csv_file)
                begin
                  date = Date.new(year, month, day)
                  import_csv_file(csv_file, date)
                rescue Date::Error
                  logger.warn("Invalid date: #{year}-#{month}-#{day}")
                  next
                end
              end
            end
          end
        end
      end

      def import_csv_file(csv_file, date)
        logger.info("Importing #{csv_file} for #{date}")

        row_count = 0
        CSV.foreach(csv_file, headers: true) do |row|
          row_count += 1
          begin
            import_row(row)
          rescue StandardError => e
            @error_count += 1
            logger.error("Error importing row #{row_count} from #{csv_file}: #{e.message}")
          end
        end

        logger.info("Processed #{row_count} rows from #{csv_file}")
      end

      def import_row(row)
        # Parse ticker to extract option details
        ticker = row['ticker']

        return unless ticker&.start_with?('O:')

        # Remove the "O:" prefix
        clean_ticker = ticker.sub(/^O:/, '')

        # Parse option symbol: SPXW231006C04200000
        # Format: [ROOT][YYMMDD][C/P][STRIKE*1000]
        match = clean_ticker.match(/^([A-Z]+)(\d{6})([CP])(\d{8})$/)
        unless match
          logger.warn("Unable to parse ticker: #{clean_ticker}")
          return
        end

        root_symbol, exp_date, put_or_call, strike_raw = match.captures

        # Skip if this doesn't match our target root symbol
        return unless root_symbol == @root_symbol

        exp_year = 2000 + exp_date[0..1].to_i
        exp_month = exp_date[2..3].to_i
        exp_day = exp_date[4..5].to_i
        expiration_date = Date.new(exp_year, exp_month, exp_day)
        strike_price = strike_raw.to_f / 1000.0
        contract_type = put_or_call == 'C' ? 'CALL' : 'PUT'

        # Convert window_start from unix nanoseconds to timestamp (in UTC)
        window_start_ns = row['window_start'].to_i
        valid_time = Time.at(window_start_ns / 1_000_000_000.0).utc

        attributes = {
          symbol: clean_ticker,
          root_symbol: root_symbol,
          underlying_symbol: @underlying_symbol,
          expiration_date: expiration_date,
          strike: strike_price,
          contract_type: contract_type,
          open_price: parse_decimal(row['open']),
          close_price: parse_decimal(row['close']),
          mark: parse_decimal(row['close']),
          last_price: parse_decimal(row['close']),
          high_price: parse_decimal(row['high']),
          low_price: parse_decimal(row['low']),
          volume: parse_integer(row['volume']),
          valid_time: valid_time,
          transaction_time: Time.current
        }

        @batch << attributes

        if @batch.size >= BATCH_SIZE
          flush_batch
        end
      end

      def parse_decimal(value)
        return nil if value.nil? || value.to_s.strip.empty?
        BigDecimal(value.to_s)
      rescue ArgumentError
        nil
      end

      def parse_integer(value)
        return nil if value.nil? || value.to_s.strip.empty?
        value.to_i
      end

      def flush_batch
        return if @batch.empty?

        begin
          count_before = OptionsTrader::OptionChainHistory.count

          # NOTE: Use upsert_all with unique_by to handle duplicates
          # This uses ON CONFLICT DO NOTHING in PostgreSQL
          OptionsTrader::OptionChainHistory.upsert_all(
            @batch,
            unique_by: [:root_symbol, :expiration_date, :strike, :contract_type, :valid_time],
            returning: false
          )

          begin
            ActiveRecord::Base.connection.execute('CHECKPOINT')
          rescue ActiveRecord::StatementInvalid => checkpoint_error
            logger.debug("CHECKPOINT skipped: #{checkpoint_error.message}") unless checkpoint_error.message.include?('permission denied')
          end

          count_after = OptionsTrader::OptionChainHistory.count
          inserted = count_after - count_before

          @imported_count += inserted
          @skipped_count += (@batch.size - inserted)

          logger.info("Batch flushed: #{inserted} inserted, #{@batch.size - inserted} skipped (duplicates)")
        rescue StandardError => e
          @error_count += @batch.size
          logger.error("Batch insert failed: #{e.message}")
          logger.debug("Batch size: #{@batch.size}")

          if e.message.include?('IndexCorrupted') || e.message.include?('unexpected zero page')
            logger.warn("Index corruption detected, attempting REINDEX...")
            begin
              ActiveRecord::Base.connection.execute('REINDEX TABLE option_chain_history')
              logger.info("REINDEX completed successfully")
            rescue => reindex_error
              logger.error("REINDEX failed: #{reindex_error.message}")
            end
          end
        ensure
          @batch.clear
        end
      end

      def log_import_summary
        logger.info("Import completed for #{@root_symbol}")
        logger.info("Records imported: #{@imported_count}")
        logger.info("Records skipped (duplicates): #{@skipped_count}")
        logger.info("Errors encountered: #{@error_count}")
      end
    end
  end
end