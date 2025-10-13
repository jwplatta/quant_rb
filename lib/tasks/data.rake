require 'active_record'

namespace :data do
  desc "Update VIX data for option chain history records"
  task :update_vix => :environment do
    puts "Updating VIX data for option chain history..."

    # TODO: Implement VIX data fetching logic
    # This task should:
    # 1. Identify records that need VIX data updates
    # 2. Fetch VIX data from your data source (API, file, etc.)
    # 3. Update the vix, vix9d, vix3m, vvix, skew columns

    # Example structure:
    # records_to_update = ActiveRecord::Base.connection.execute(
    #   "SELECT DISTINCT valid_time::date as date FROM option_chain_history WHERE vix IS NULL"
    # )
    #
    # records_to_update.each do |record|
    #   date = record['date']
    #   vix_data = fetch_vix_data_for_date(date)  # Your implementation
    #
    #   if vix_data
    #     ActiveRecord::Base.connection.execute(<<-SQL)
    #       UPDATE option_chain_history
    #       SET vix = #{vix_data[:vix]},
    #           vix9d = #{vix_data[:vix9d]},
    #           vix3m = #{vix_data[:vix3m]},
    #           vvix = #{vix_data[:vvix]},
    #           skew = #{vix_data[:skew]}
    #       WHERE valid_time::date = '#{date}'
    #     SQL
    #     puts "Updated VIX data for #{date}"
    #   end
    # end

    puts "VIX data update completed"
  end

  desc "Backfill VIX data for all historical records"
  task :backfill_vix => :environment do
    puts "Starting VIX data backfill for all historical records..."

    # TODO: Implement comprehensive backfill logic
    # This could be similar to update_vix but for ALL records, not just missing ones
    # Consider batching for large datasets

    puts "VIX data backfill completed"
  end

  desc "Validate VIX data integrity"
  task :validate_vix => :environment do
    puts "Validating VIX data integrity..."

    # Check for missing VIX data
    missing_count = ActiveRecord::Base.connection.execute(
      "SELECT COUNT(*) as count FROM option_chain_history WHERE vix IS NULL"
    ).first['count']
    puts "Records missing VIX data: #{missing_count}"

    # Check for invalid VIX values (e.g., negative values)
    invalid_count = ActiveRecord::Base.connection.execute(
      "SELECT COUNT(*) as count FROM option_chain_history WHERE vix < 0 OR vix > 200"
    ).first['count']
    puts "Records with invalid VIX values: #{invalid_count}"

    # TODO: Add more validation checks as needed

    puts "VIX data validation completed"
  end

  desc "Clean up duplicate or invalid data"
  task :cleanup => :environment do
    puts "Starting data cleanup..."

    # TODO: Implement cleanup logic
    # - Remove duplicate records
    # - Fix data inconsistencies
    # - Handle edge cases

    puts "Data cleanup completed"
  end

  desc "Export option chain data to CSV"
  task :export_csv, [:filename] => :environment do |t, args|
    filename = args[:filename] || "option_chain_export_#{Time.now.strftime('%Y%m%d_%H%M%S')}.csv"

    puts "Exporting option chain data to #{filename}..."

    underlying_symbol = args[:underlying_symbol]
    valid_time = args[:valid_time]
    expiration_date = args[:expiration_date]

    # TODO: Implement CSV export
    # - Query option_chain_history data
    # - Write to CSV with proper headers
    # - Include VIX data and source information

    puts "Export completed: #{filename}"
  end

  desc "Import price history data for a symbol"
  task :import_price_history, [:symbol, :start_date, :end_date, :interval] => :environment do |t, args|
    symbol = args[:symbol]
    start_date = args[:start_date]
    end_date = args[:end_date]
    interval = args[:interval]

    unless symbol && start_date && end_date && interval
      puts "Usage: rake data:import_price_history[SYMBOL,START_DATE,END_DATE,INTERVAL]"
      puts "Example: rake \"data:import_price_history[\\$VIX,2023-01-01,2023-01-31,1min]\""
      puts "Available intervals: 1min, 5min, 10min, daily"
      exit 1
    end

    begin
      start_datetime = Date.parse(start_date).beginning_of_day
      end_datetime = Date.parse(end_date).end_of_day
    rescue ArgumentError => e
      puts "Error parsing dates: #{e.message}"
      puts "Use format: YYYY-MM-DD"
      exit 1
    end

    # Validate interval
    valid_intervals = [
      OptionsTrader::Intervals::ONE_MIN,
      OptionsTrader::Intervals::FIVE_MIN,
      OptionsTrader::Intervals::TEN_MIN,
      OptionsTrader::Intervals::DAILY
    ]

    unless valid_intervals.include?(interval)
      puts "Invalid interval: #{interval}"
      puts "Available intervals: #{valid_intervals.join(', ')}"
      exit 1
    end

    puts "Importing price history for #{symbol}"
    puts "Date range: #{start_datetime} to #{end_datetime}"
    puts "Interval: #{interval}"
    puts "=" * 50

    begin
      # Initialize the historical markets service with Schwab provider
      require_relative '../../lib/options_trader'
      schwab_provider = OptionsTrader::DataProviders::Schwab::Markets.new
      historical_service = OptionsTrader::Services::HistoricalMarkets.new(provider: schwab_provider)

      # Fetch price history data
      puts "Fetching data from Schwab API..."
      price_data = historical_service.get_price_history_by_interval(
        symbol: symbol,
        start_datetime: start_datetime,
        end_datetime: end_datetime,
        interval: interval
      )

      if price_data.nil? || (price_data.respond_to?(:empty?) && price_data.empty?)
        puts "No data returned from API"
        exit 0
      end

      # Handle the data structure (assuming it's an array of price objects)
      imported_count = 0
      skipped_count = 0

      puts "Processing #{price_data.length} records..."

      price_data.each_with_index do |price_record, index|
        # Extract data from the price record object
        # Note: Adjust these based on the actual structure returned by Schwab API
        timestamp = price_record.datetime || price_record.timestamp
        open_price = price_record.open
        close_price = price_record.close
        high_price = price_record.high
        low_price = price_record.low
        volume = price_record.volume

        # Check if record already exists
        existing_record = ActiveRecord::Base.connection.execute(
          "SELECT 1 FROM price_history WHERE symbol = '#{symbol}' AND valid_time = '#{timestamp}' LIMIT 1"
        )

        if existing_record.any?
          skipped_count += 1
          next
        end

        # Insert new record
        ActiveRecord::Base.connection.execute(<<-SQL)
          INSERT INTO price_history (symbol, open, close, high, low, volume, valid_time, transaction_time)
          VALUES ('#{symbol}', #{open_price}, #{close_price}, #{high_price}, #{low_price}, #{volume}, '#{timestamp}', CURRENT_TIMESTAMP)
        SQL

        imported_count += 1

        # Progress indicator
        if (index + 1) % 100 == 0
          puts "Processed #{index + 1} records..."
        end
      end

      puts "=" * 50
      puts "Import completed!"
      puts "Records imported: #{imported_count}"
      puts "Records skipped (duplicates): #{skipped_count}"
      puts "Total processed: #{imported_count + skipped_count}"

    rescue => e
      puts "Error during import: #{e.message}"
      puts e.backtrace.join("\n")
      exit 1
    end
  end

  desc "Show data statistics"
  task :stats => :environment do
    puts "Option Chain History Data Statistics"
    puts "=" * 50

    # Total records
    total_records = ActiveRecord::Base.connection.execute(
      "SELECT COUNT(*) as count FROM option_chain_history"
    ).first['count']
    puts "Total records: #{total_records.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"

    # Records by source
    puts "\nRecords by source:"
    ActiveRecord::Base.connection.execute(
      "SELECT source, COUNT(*) as count FROM option_chain_history GROUP BY source ORDER BY count DESC"
    ).each do |row|
      source = row['source'] || 'NULL'
      count = row['count'].to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      puts "  #{source}: #{count}"
    end

    # VIX data coverage
    vix_coverage = ActiveRecord::Base.connection.execute(
      "SELECT COUNT(*) as count FROM option_chain_history WHERE vix IS NOT NULL"
    ).first['count']
    coverage_pct = total_records.to_i > 0 ? (vix_coverage.to_f / total_records.to_f * 100).round(2) : 0
    puts "\nVIX data coverage: #{vix_coverage.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} records (#{coverage_pct}%)"

    # Date range
    date_range = ActiveRecord::Base.connection.execute(
      "SELECT MIN(valid_time) as min_date, MAX(valid_time) as max_date FROM option_chain_history"
    ).first
    puts "\nDate range: #{date_range['min_date']} to #{date_range['max_date']}"

    # Price history stats
    puts "\nPrice History Data Statistics"
    puts "=" * 50

    price_total = ActiveRecord::Base.connection.execute(
      "SELECT COUNT(*) as count FROM price_history"
    ).first['count']
    puts "Total price history records: #{price_total.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"

    if price_total.to_i > 0
      # Symbols in price history
      puts "\nSymbols in price history:"
      ActiveRecord::Base.connection.execute(
        "SELECT symbol, COUNT(*) as count FROM price_history GROUP BY symbol ORDER BY count DESC"
      ).each do |row|
        symbol = row['symbol']
        count = row['count'].to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
        puts "  #{symbol}: #{count}"
      end

      # Price history date range
      price_date_range = ActiveRecord::Base.connection.execute(
        "SELECT MIN(valid_time) as min_date, MAX(valid_time) as max_date FROM price_history"
      ).first
      puts "\nPrice history date range: #{price_date_range['min_date']} to #{price_date_range['max_date']}"
    end
  end
end