namespace :polygon do
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
    day = args[:day]&.to_i

    puts "Starting Polygon import..."
    puts "Root Symbol: #{root_symbol}"
    puts "Underlying Symbol: #{underlying_symbol}"

    if year && month && day
      puts "Date: #{year}-#{sprintf('%02d', month)}-#{sprintf('%02d', day)}"
    else
      puts "Date: All available data"
    end
    puts ""

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

  desc "Import SPXW data for all available dates"
  task :import_spxw_all => :environment do
    puts "Starting full SPXW import..."

    importer = OptionsTrader::Services::PolygonImporter.new(
      root_symbol: 'SPXW',
      underlying_symbol: 'SPX'
    )

    begin
      importer.import!
      puts "\nSPXW import completed successfully!"
    rescue StandardError => e
      puts "\nSPXW import failed: #{e.message}"
      puts e.backtrace.join("\n") if ENV['DEBUG']
      exit 1
    end
  end

  desc "Import SPXW data for a specific date"
  task :import_spxw_date, [:year, :month, :day] => :environment do |t, args|
    unless args[:year] && args[:month] && args[:day]
      puts "Usage: rake polygon:import_spxw_date[YEAR,MONTH,DAY]"
      puts "Example: rake polygon:import_spxw_date[2023,10,6]"
      exit 1
    end

    year = args[:year].to_i
    month = args[:month].to_i
    day = args[:day].to_i

    puts "Starting SPXW import for #{year}-#{sprintf('%02d', month)}-#{sprintf('%02d', day)}..."

    importer = OptionsTrader::Services::PolygonImporter.new(
      root_symbol: 'SPXW',
      underlying_symbol: 'SPX',
      year: year,
      month: month,
      day: day
    )

    begin
      importer.import!
      puts "\nSPXW import completed successfully!"
    rescue StandardError => e
      puts "\nSPXW import failed: #{e.message}"
      puts e.backtrace.join("\n") if ENV['DEBUG']
      exit 1
    end
  end

  desc "Show import status and statistics"
  task :status => :environment do
    puts "Polygon Import Status"
    puts "=" * 50

    total_records = OptionsTrader::OptionChainHistory.count
    puts "Total records in option_chain_history: #{total_records}"

    if total_records > 0
      # Show records by root symbol
      puts "\nRecords by root symbol:"
      OptionsTrader::OptionChainHistory.group(:root_symbol).count.each do |symbol, count|
        puts "  #{symbol}: #{count} records"
      end

      # Show date range
      earliest = OptionsTrader::OptionChainHistory.minimum(:valid_time)
      latest = OptionsTrader::OptionChainHistory.maximum(:valid_time)
      puts "\nDate range:"
      puts "  Earliest: #{earliest}"
      puts "  Latest: #{latest}"

      # Show contract types
      puts "\nContract types:"
      OptionsTrader::OptionChainHistory.group(:contract_type).count.each do |type, count|
        puts "  #{type}: #{count} records"
      end
    end
  end
end