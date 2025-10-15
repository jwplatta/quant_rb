# Rake tasks for managing Polygon.io data import and analysis
#
# These tasks work with historical options data downloaded from Polygon.io
# and stored in CSV format on the local filesystem.
namespace :polygon do
  # Import minute-level options aggregates data from local CSV files
  #
  # This task imports historical options data that has been previously downloaded
  # from Polygon.io and stored in CSV format. The data is organized in a directory
  # structure by date: BASE_DATA_PATH/YYYY/MM/DD/SYMBOL.csv
  #
  # @param root_symbol [String] Option root symbol (e.g., 'SPXW')
  # @param underlying_symbol [String] Underlying asset symbol (e.g., 'SPX') 
  # @param year [Integer] Year to import (optional)
  # @param month [Integer] Month to import (optional)
  # @param day [Integer] Day to import (optional)
  #
  # @example Import all available SPXW data
  #   rake polygon:import[SPXW,SPX]
  #
  # @example Import specific date
  #   rake polygon:import[SPXW,SPX,2023,10,6]
  desc "Import polygon minute aggregates data for a specific symbol"
  task :import, [:root_symbol, :underlying_symbol, :year, :month, :day] => :environment do |t, args|
    unless args[:root_symbol] && args[:underlying_symbol]
      puts "Usage: rake polygon:import[ROOT_SYMBOL,UNDERLYING_SYMBOL,YEAR,MONTH,DAY]"
      puts "  ROOT_SYMBOL and UNDERLYING_SYMBOL are required"
      puts "  YEAR, MONTH, DAY are optional - if not provided, imports all available data"
      puts ""
      puts "Examples:"
      puts "  rake polygon:import[SPXW,SPX]                    # Import all SPXW data"
      puts "  rake polygon:import[SPXW,SPX,2023,10,6]          # Import specific date"
      exit 1
    end

    root_symbol = args[:root_symbol]
    underlying_symbol = args[:underlying_symbol]
    year = args[:year]&.to_i
    month = args[:month]&.to_i
    day = args[:day]&.to_i || 1

    puts "Starting Polygon import..."
    puts "Root Symbol: #{root_symbol}"
    puts "Underlying Symbol: #{underlying_symbol}"

    if year && month && day
      puts "Date: #{year}-#{sprintf('%02d', month)}-#{sprintf('%02d', day)}"
    elsif year && month
      puts "Date: #{year}-#{sprintf('%02d', month)}"
    else
      puts "Date: All available data"
    end

    importer = OptionsTrader::Services::PolygonImporter.new(
      root_symbol: root_symbol,
      underlying_symbol: underlying_symbol,
      year: year,
      month: month,
      day: day
    )

    begin
      importer.import!
      puts "\nImport completed successfully!"
    rescue StandardError => e
      puts "\nImport failed: #{e.message}"
      puts e.backtrace.join("\n") if ENV['DEBUG']
      exit 1
    end
  end

  # Display import status and statistics for option chain history data
  #
  # Shows overview of imported data including:
  # - Total record count
  # - Records by root symbol
  # - Date range of available data  
  # - Contract type breakdown (calls vs puts)
  #
  # @example
  #   rake polygon:status
  desc "Show import status and statistics"
  task :status => :environment do
    puts "Polygon Import Status"
    puts "=" * 50

    total_records = OptionsTrader::OptionChainHistory.count
    puts "Total records in option_chain_history: #{total_records}"

    if total_records > 0
      puts "\nRecords by root symbol:"
      OptionsTrader::OptionChainHistory.group(:root_symbol).count.each do |symbol, count|
        puts "  #{symbol}: #{count} records"
      end

      earliest = OptionsTrader::OptionChainHistory.minimum(:valid_time)
      latest = OptionsTrader::OptionChainHistory.maximum(:valid_time)
      puts "\nDate range:"
      puts "  Earliest: #{earliest}"
      puts "  Latest: #{latest}"

      puts "\nContract types:"
      OptionsTrader::OptionChainHistory.group(:contract_type).count.each do |type, count|
        puts "  #{type}: #{count} records"
      end
    end
  end

  # Download day-level aggregates for a date range from Polygon.io API
  #
  # Downloads daily aggregated options data directly from Polygon.io API
  # and saves it to local CSV files. Requires POLYGON_FILES_PATH environment
  # variable to specify the download directory.
  #
  # @param start_date [String] Start date in YYYY-MM-DD format
  # @param end_date [String] End date in YYYY-MM-DD format
  #
  # @example Download Q4 2023 data
  #   POLYGON_FILES_PATH=/path/to/data rake polygon:download_day_aggs[2023-10-01,2023-12-31]
  desc "Download day aggregates for a date range"
  task :download_day_aggs, [:start_date, :end_date] => :environment do |t, args|
    unless args[:start_date] && args[:end_date]
      puts "Usage: rake polygon:download_day_aggs[start_date,end_date]"
      puts "Date format: YYYY-MM-DD"
      puts "Example: rake polygon:download_day_aggs[2023-01-01,2023-12-31]"
      exit 1
    end

    begin
      start_date = Date.parse(args[:start_date])
      end_date = Date.parse(args[:end_date])
    rescue ArgumentError => e
      puts "Error parsing dates: #{e.message}"
      puts "Please use YYYY-MM-DD format"
      exit 1
    end

    if start_date > end_date
      puts "Error: Start date must be before or equal to end date"
      exit 1
    end

    dir = ENV["POLYGON_FILES_PATH"]
    unless dir
      puts "Error: POLYGON_FILES_PATH environment variable is required"
      exit 1
    end

    client = OptionsTrader::DataProviders::Polygon::Client.instance
    puts "Downloading day aggregates from #{start_date} to #{end_date} to #{dir}"

    (start_date..end_date).each do |date|
      year = date.year
      month = date.strftime('%m')
      filename = "#{date.strftime('%Y-%m-%d')}.csv"
      expected_csv_path = File.join(dir, "day_aggs_v1", year.to_s, month, filename)

      if File.exist?(expected_csv_path)
        puts "Skipping #{date} - file already exists: #{expected_csv_path}"
        next
      end

      puts "Downloading day aggs for #{date}"
      begin
        client.download_day_aggs(date, local_dir: dir)
        puts "  Downloaded and extracted to: #{expected_csv_path}"
      rescue StandardError => e
        puts "  Error downloading day aggs for #{date}: #{e.message}"
      end
    end

    puts "Done"
  end

  # Download minute-level aggregates for a date range from Polygon.io API
  #
  # Downloads minute-by-minute aggregated options data directly from Polygon.io API
  # and saves it to local CSV files. This provides higher granularity than day aggregates.
  # Requires POLYGON_FILES_PATH environment variable to specify the download directory.
  #
  # @param start_date [String] Start date in YYYY-MM-DD format
  # @param end_date [String] End date in YYYY-MM-DD format
  #
  # @example Download a single week of minute data
  #   POLYGON_FILES_PATH=/path/to/data rake polygon:download_min_aggs[2023-10-01,2023-10-07]
  desc "Download minute aggregates for a date range"
  task :download_min_aggs, [:start_date, :end_date] => :environment do |t, args|
    unless args[:start_date] && args[:end_date]
      puts "Usage: rake polygon:download_min_aggs[start_date,end_date]"
      puts "Date format: YYYY-MM-DD"
      puts "Example: rake polygon:download_min_aggs[2023-01-01,2023-12-31]"
      exit 1
    end

    begin
      start_date = Date.parse(args[:start_date])
      end_date = Date.parse(args[:end_date])
    rescue ArgumentError => e
      puts "Error parsing dates: #{e.message}"
      puts "Please use YYYY-MM-DD format"
      exit 1
    end

    if start_date > end_date
      puts "Error: Start date must be before or equal to end date"
      exit 1
    end

    dir = ENV["POLYGON_FILES_PATH"]
    unless dir
      puts "Error: POLYGON_FILES_PATH environment variable is required"
      exit 1
    end

    client = OptionsTrader::DataProviders::Polygon::Client.instance
    puts "Downloading minute aggregates from #{start_date} to #{end_date} to #{dir}"

    (start_date..end_date).each do |date|
      year = date.year
      month = date.strftime('%m')
      filename = "#{date.strftime('%Y-%m-%d')}.csv"
      expected_csv_path = File.join(dir, "minute_aggs_v1", year.to_s, month, filename)

      if File.exist?(expected_csv_path)
        puts "Skipping #{date} - file already exists: #{expected_csv_path}"
        next
      end

      puts "Downloading minute aggs for #{date}"
      begin
        client.download_min_aggs(date, local_dir: dir)
        puts "  Downloaded and extracted to: #{expected_csv_path}"
      rescue StandardError => e
        puts "  Error downloading minute aggs for #{date}: #{e.message}"
      end
    end

    puts "Done"
  end
end