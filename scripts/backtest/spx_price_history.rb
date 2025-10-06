#!/usr/bin/env ruby
# frozen_string_literal: true

# SPX Price History Downloader
# ============================
#
# This script downloads historical price data for the S&P 500 Index ($SPX) using
# the Schwab API and exports it to CSV format for analysis.
#
# FEATURES:
# ---------
# • Downloads 5-minute interval price candles for specified date ranges
# • Exports data to CSV with dynamic headers based on candle object attributes
# • Automatic filename generation based on date range
# • Custom output file support
# • Proper datetime handling (start of day to end of day)
# • Comprehensive error handling and logging
#
# USAGE:
# ------
# Basic usage (uses default date range):
#   ruby scripts/spx_price_history.rb
#
# Specific date range:
#   ruby scripts/spx_price_history.rb --start-date 2023-09-26 --end-date 2023-09-27
#
# Custom output file:
#   ruby scripts/spx_price_history.rb --start-date 2023-09-26 -o my_data.csv
#
# Show help:
#   ruby scripts/spx_price_history.rb --help
#
# OUTPUT:
# -------
# CSV file with columns dynamically generated from candle attributes, typically:
# • datetime - Timestamp (YYYY-MM-DD HH:MM:SS format)
# • open - Opening price
# • high - High price
# • low - Low price
# • close - Closing price
# • volume - Trading volume
# • Plus any additional attributes available on the candle objects
#
# DEPENDENCIES:
# -------------
# • Schwab API credentials configured in .env file
# • Valid Schwab API token
# • OptionsTrader gem and dependencies
#
# ARCHITECTURE:
# -------------
# Uses the service-oriented architecture pattern:
# • HistoricalMarkets service for business logic
# • Schwab Markets data provider for API calls
# • Separation of concerns with dependency injection
#
# AUTHOR: jwplatta
# DATE: 2025-10-04

require_relative '../lib/options_trader'
require 'date'
require 'logger'
require 'pry'
require 'optparse'
require 'csv'

class SPXPriceHistory
  def initialize
    @logger = Logger.new(STDOUT)
    @logger.level = Logger::INFO
    @logger.formatter = proc do |severity, datetime, progname, msg|
      "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} [#{severity}] #{msg}\n"
    end

    schwab_provider = OptionsTrader::DataProviders::Schwab::Markets.new
    @historical_markets = OptionsTrader::Services::HistoricalMarkets.new(provider: schwab_provider)
  end

  def download(start_date, end_date, output_file: nil)
    @logger.info("Downloading SPX price history from #{start_date} to #{end_date}")

    # Convert dates to DateTime objects with proper time boundaries
    # Start date: beginning of day (00:00:00)
    start_datetime = case start_date
                     when Date
                       start_date.to_datetime.beginning_of_day
                     when String
                       Date.parse(start_date).to_datetime.beginning_of_day
                     else
                       start_date
                     end

    # End date: end of day (23:59:59.999)
    end_datetime = case end_date
                   when Date
                     end_date.to_datetime.end_of_day
                   when String
                     Date.parse(end_date).to_datetime.end_of_day
                   else
                     end_date
                   end

    @logger.info("Date range: #{start_datetime} to #{end_datetime}")

    price_hist = @historical_markets.get_price_history_every_five_min(
      symbol: '$SPX',
      start_datetime: start_datetime,
      end_datetime: end_datetime
    )

    candles = price_hist&.candles || []
    @logger.info("Retrieved #{candles.length} price candles")

    if candles.empty?
      @logger.warn("No price data retrieved for the specified date range")
      return false
    end

    if output_file.nil?
      # Find actual date range from returned candles
      actual_start, actual_end = get_actual_date_range(candles)
      start_str = actual_start.strftime('%Y%m%d')
      end_str = actual_end.strftime('%Y%m%d')
      output_file = "spx_price_history_#{start_str}_#{end_str}.csv"
      @logger.info("Using actual data range for filename: #{actual_start.strftime('%Y-%m-%d')} to #{actual_end.strftime('%Y-%m-%d')}")
    end

    write_candles_to_csv(candles, output_file)

    @logger.info("Price history saved to: #{output_file}")

    true
  rescue StandardError => e
    @logger.error("Failed to download SPX price history: #{e.message}")
    @logger.debug(e.backtrace.join("\n"))
    false
  end

  private

  def get_actual_date_range(candles)
    return [Date.current, Date.current] if candles.empty?

    # Extract all datetime values from candles
    datetimes = candles.map do |candle|
      datetime = candle.respond_to?(:datetime) ? candle.datetime : candle.timestamp
      datetime.to_date
    end

    # Find min and max dates
    min_date = datetimes.min
    max_date = datetimes.max

    [min_date, max_date]
  end

  def write_candles_to_csv(candles, filename)
    return if candles.empty?

    first_candle = candles.first
    headers = get_candle_headers(first_candle)

    CSV.open(filename, 'w', write_headers: true, headers: headers) do |csv|
      candles.each do |candle|
        row_data = headers.map do |header|
          get_candle_value(candle, header)
        end
        csv << row_data
      end
    end
  end

  def get_candle_headers(candle)
    %w[open close high low volume datetime_ms]
  end

  def get_candle_value(candle, header)
    case header
    when 'datetime_ms'
      # Convert datetime to UTC milliseconds since epoch
      datetime = candle.respond_to?(:datetime) ? candle.datetime : candle.timestamp
      datetime.to_time.utc.to_i * 1000
    else
      candle.send(header)
    end
  rescue StandardError
    nil
  end
end

if __FILE__ == $0
  default_start = Date.new(2025, 8, 1)
  default_end = Date.new(2025, 8, 29)

  options = {
    start_date: default_start,
    end_date: default_end,
    output_file: nil
  }

  OptionParser.new do |opts|
    opts.banner = "Usage: ruby scripts/spx_price_history.rb [options]"
    opts.separator ""
    opts.separator "Options:"

    opts.on("--start-date DATE", "Start date (YYYY-MM-DD format)") do |date|
      begin
        options[:start_date] = Date.parse(date)
      rescue Date::Error
        puts "Error: Invalid start date format. Use YYYY-MM-DD (e.g., 2023-09-26)"
        exit 1
      end
    end

    opts.on("--end-date DATE", "End date (YYYY-MM-DD format)") do |date|
      begin
        options[:end_date] = Date.parse(date)
      rescue Date::Error
        puts "Error: Invalid end date format. Use YYYY-MM-DD (e.g., 2023-09-27)"
        exit 1
      end
    end

    opts.on("-o", "--output FILE", "Output CSV file (default: auto-generated)") do |file|
      options[:output_file] = file
    end

    opts.on("-h", "--help", "Show this help message") do
      puts opts
      exit 0
    end

    opts.separator ""
    opts.separator "Examples:"
    opts.separator "  ruby scripts/spx_price_history.rb --start-date 2023-09-26 --end-date 2023-09-27"
    opts.separator "  ruby scripts/spx_price_history.rb --start-date 2023-09-26 -o my_data.csv"
    opts.separator "  ruby scripts/spx_price_history.rb"
  end.parse!

  # Validate date range
  if options[:start_date] > options[:end_date]
    puts "Error: Start date must be before or equal to end date"
    exit 1
  end

  puts "SPX Price History Downloader"
  puts "Start Date: #{options[:start_date]} (00:00:00)"
  puts "End Date: #{options[:end_date]} (23:59:59)"

  output_file = options[:output_file]
  if output_file
    puts "Output File: #{output_file}"
  else
    start_str = options[:start_date].strftime('%Y%m%d')
    end_str = options[:end_date].strftime('%Y%m%d')
    output_file = "spx_price_history_#{start_str}_#{end_str}.csv"
    puts "Output File: #{output_file} (auto-generated)"
  end
  puts ""

  history = SPXPriceHistory.new
  success = history.download(options[:start_date], options[:end_date], output_file: options[:output_file])

  exit(success ? 0 : 1)
end
