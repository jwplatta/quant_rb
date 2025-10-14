require 'csv'
require 'date'


namespace :data do
  desc "Import price history data from CSV files"
  task :import_price_history, [:symbol, :start_date, :end_date, :interval] => :environment do |t, args|

    symbol = args[:symbol]
    start_date = args[:start_date]
    end_date = args[:end_date] || start_date
    interval = args[:interval]

    unless symbol && start_date && interval
      puts "Usage: rake data:import_price_history[SYMBOL,START_DATE,END_DATE,INTERVAL] or rake data:import_price_history[SYMBOL,START_DATE,,INTERVAL]"
      puts "Example: rake \"data:import_price_history[AAPL,2023-09-26,,1min]\" or rake \"data:import_price_history[AAPL,2023-09-26,2023-09-30,5min]\""
      puts "Available intervals: 1min, 5min, 10min"
      exit 1
    end

    unless OptionsTrader::Intervals::ALL_INTERVALS.include?(interval)
      puts "Invalid interval: #{interval}"
      puts "Available intervals: #{valid_intervals.join(', ')}"
      exit 1
    end

    base_path = ENV['HISTORICAL_FLATFILES_PATH']
    unless base_path
      puts "HISTORICAL_FLATFILES_PATH environment variable not set"
      exit 1
    end

    unless Dir.exist?(base_path)
      puts "Directory does not exist: #{base_path}"
      exit 1
    end

    begin
      start_date_obj = Date.parse(start_date)
      end_date_obj = Date.parse(end_date)

      date_range = if interval == 'daily'
        start_year = start_date_obj.year
        end_year = end_date_obj.year

        (start_year..end_year).map { |year| Date.new(year, 1, 1) }
      else
        (start_date_obj..end_date_obj).to_a
      end
    rescue ArgumentError => e
      puts "Error parsing dates: #{e.message}"
      puts "Use format: YYYY-MM-DD"
      exit 1
    end

    if end_date_obj < start_date_obj
      puts "End date must be greater than or equal to start date"
      exit 1
    end

    puts "Importing price history for #{symbol}"
    puts "Date range: #{start_date_obj} to #{end_date_obj}"
    puts "Interval: #{interval}"
    puts "Base path: #{base_path}"
    puts "=" * 50

    total_imported = 0
    total_skipped = 0

    date_range.each do |date|
      year = date.year
      month = date.month.to_s.rjust(2, '0')
      day = date.day.to_s.rjust(2, '0')

      if interval == 'daily'
        csv_file_path = File.join(base_path, interval, year.to_s, "#{symbol}.csv")
      else
        csv_file_path = File.join(base_path, interval, year.to_s, month, day, "#{symbol}.csv")
      end

      unless File.exist?(csv_file_path)
        puts "No CSV file found: #{csv_file_path}"
        next
      end

      puts "Processing #{csv_file_path}..."

      begin
        imported_count = 0
        skipped_count = 0

        CSV.foreach(csv_file_path, headers: true) do |row|
          # Headers: symbol,datetime_ms,datetime_str,open,close,high,low,volume
          datetime_ms = row['datetime_ms'].to_i
          valid_time = Time.at(datetime_ms / 1000.0).utc

          existing = OptionsTrader::PriceHistory.find_by(
            symbol: symbol,
            valid_time: valid_time,
            interval: interval
          )

          if existing
            skipped_count += 1
            next
          end

          OptionsTrader::PriceHistory.create!(
            symbol: symbol,
            open: row['open'].to_f,
            close: row['close'].to_f,
            high: row['high'].to_f,
            low: row['low'].to_f,
            volume: row['volume'].to_i,
            interval: interval,
            valid_time: valid_time
          )

          imported_count += 1
        end

        puts "  Imported: #{imported_count}, Skipped: #{skipped_count}"
        total_imported += imported_count
        total_skipped += skipped_count

      rescue => e
        puts "Error processing file #{csv_file_path}: #{e.message}"
        next
      end
    end

    puts "=" * 50
    puts "Import completed!"
    puts "Total records imported: #{total_imported}"
    puts "Total records skipped (duplicates): #{total_skipped}"
    puts "Total processed: #{total_imported + total_skipped}"
  end
end
