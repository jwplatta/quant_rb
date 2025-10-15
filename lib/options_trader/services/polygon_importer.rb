require 'csv'
require 'date'

module OptionsTrader
  module Services
    # Imports historical options data from Polygon.io minute aggregates CSV files
    # into the OptionChainHistory table.
    #
    # The importer processes CSV files organized in a directory structure:
    #   BASE_DATA_PATH/YYYY/MM/DD/SYMBOL.csv
    #
    # Each CSV file contains minute-level option aggregates with columns:
    #   - ticker: Option symbol (e.g., "O:SPXW231006C04200000")
    #   - window_start: Unix timestamp in nanoseconds
    #   - open, close, high, low: Price data
    #   - volume: Trading volume
    #
    # @example Import all available SPXW data
    #   importer = PolygonImporter.new(root_symbol: 'SPXW', underlying_symbol: 'SPX')
    #   importer.import!
    #
    # @example Import specific date
    #   importer = PolygonImporter.new(
    #     root_symbol: 'SPXW', 
    #     underlying_symbol: 'SPX',
    #     year: 2023, month: 10, day: 6
    #   )
    #   importer.import!
    class PolygonImporter
      include OptionsTrader::Loggable

      # Data source identifier for imported records
      SOURCE = 'polygon'.freeze
      
      # Base path where Polygon minute aggregates CSV files are stored
      BASE_DATA_PATH = '/Volumes/ext_docs/options_trader/polygon/minute_aggs_v1'
      
      # Number of records to batch before database insert
      BATCH_SIZE = 1000

      # Initialize a new Polygon importer
      #
      # @param root_symbol [String] Option root symbol (e.g., 'SPXW')
      # @param underlying_symbol [String] Underlying asset symbol (e.g., 'SPX')
      # @param year [Integer, nil] Specific year to import (optional)
      # @param month [Integer, nil] Specific month to import (optional)
      # @param day [Integer, nil] Specific day to import (optional)
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

      # Start the import process for the configured symbol and date range
      #
      # This method orchestrates the entire import workflow:
      # 1. Validates the data path exists
      # 2. Imports either a specific date or all available data
      # 3. Flushes any remaining batched records
      # 4. Logs import statistics
      #
      # @raise [StandardError] if data path doesn't exist or import fails
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

      # Validates that the base data path exists
      #
      # @raise [StandardError] if the data path doesn't exist
      def validate_data_path!
        unless Dir.exist?(BASE_DATA_PATH)
          raise "Data path does not exist: #{BASE_DATA_PATH}"
        end
      end

      # Checks if user requested import for a specific date
      #
      # @return [Boolean] true if year, month, and day are all specified
      def specific_date_requested?
        @year && @month && @day
      end

      # Imports data for a specific date by looking for the corresponding CSV file
      #
      # Expected file path: BASE_DATA_PATH/YYYY/MM/DD/ROOT_SYMBOL.csv
      def import_specific_date
        date_path = File.join(BASE_DATA_PATH, @year.to_s, sprintf('%02d', @month), sprintf('%02d', @day))
        csv_file = File.join(date_path, "#{@root_symbol}.csv")

        if File.exist?(csv_file)
          import_csv_file(csv_file, Date.new(@year, @month, @day))
        else
          logger.warn("CSV file not found: #{csv_file}")
        end
      end

      # Imports all available data by recursively scanning directory structure
      #
      # Walks through the directory tree: BASE_DATA_PATH/YYYY/MM/DD/
      # and processes any CSV files matching the root symbol
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

      # Processes a single CSV file and imports all valid option records
      #
      # @param csv_file [String] Path to the CSV file to process
      # @param date [Date] Trading date for the data
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

      # Processes a single CSV row and adds it to the batch for database insertion
      #
      # This method:
      # 1. Parses the option ticker symbol to extract contract details
      # 2. Converts timestamps and price data to appropriate formats
      # 3. Adds the record to the batch for bulk insertion
      #
      # Option ticker format: O:SPXW231006C04200000
      # - O: prefix indicates options
      # - SPXW: root symbol
      # - 231006: expiration date (YYMMDD)
      # - C: call option (P for put)
      # - 04200000: strike price * 1000 (4200.0)
      #
      # @param row [CSV::Row] CSV row containing option data
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
          transaction_time: Time.current,
          source: SOURCE
        }

        @batch << attributes

        if @batch.size >= BATCH_SIZE
          flush_batch
        end
      end

      # Safely parses a decimal value from CSV data
      #
      # @param value [String, nil] Raw value from CSV
      # @return [BigDecimal, nil] Parsed decimal or nil if invalid
      def parse_decimal(value)
        return nil if value.nil? || value.to_s.strip.empty?
        BigDecimal(value.to_s)
      rescue ArgumentError
        nil
      end

      # Safely parses an integer value from CSV data
      #
      # @param value [String, nil] Raw value from CSV
      # @return [Integer, nil] Parsed integer or nil if invalid
      def parse_integer(value)
        return nil if value.nil? || value.to_s.strip.empty?
        value.to_i
      end

      # Flushes the current batch of records to the database using bulk upsert
      #
      # This method uses ActiveRecord's upsert_all to handle duplicate records
      # gracefully with ON CONFLICT DO NOTHING behavior. It also includes
      # error handling for database corruption issues and performance logging.
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

      # Logs a summary of the import operation with statistics
      def log_import_summary
        logger.info("Import completed for #{@root_symbol}")
        logger.info("Records imported: #{@imported_count}")
        logger.info("Records skipped (duplicates): #{@skipped_count}")
        logger.info("Errors encountered: #{@error_count}")
      end
    end
  end
end