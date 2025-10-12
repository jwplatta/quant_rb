#!/usr/bin/env ruby
# frozen_string_literal: true

# Underlying Price Updater for Options Backtest Data
# ==================================================
#
# This script updates the underlying_price field in the option_chain_history table
# using historical SPX price data for SPXW options backtesting.
#
# FEATURES:
# ---------
# " Loads historical SPX price data from CSV file
# " Converts Unix millisecond timestamps to DateTime objects
# " Matches option valid_time with most recent SPX price data
# " Updates underlying_price field for $SPX underlying symbol records
# " Scopes query by earliest date in SPX data
# " Batch processing for performance with progress tracking
# " Comprehensive logging and error handling
#
# USAGE:
# ------
# Update all SPXW options with underlying prices:
#   RAILS_ENV=development RACK_ENV=development ruby scripts/backtest/update_underlying_price.rb
#
# Update specific date range:
#   RAILS_ENV=development RACK_ENV=development ruby scripts/backtest/update_underlying_price.rb --start-date 2023-09-26 --end-date 2023-09-27
#
# Dry run (no database updates):
#   RAILS_ENV=development RACK_ENV=development ruby scripts/backtest/update_underlying_price.rb --dry-run
#
# NOTE: You MUST set RAILS_ENV=development and RACK_ENV=development to connect to the
# local backtest database instead of the production Supabase database.
#
# DEPENDENCIES:
# -------------
# " Historical SPX price data at /Volumes/ext_docs/options_trader/historical/indexes/SPX.csv
# " Local PostgreSQL database with option_chain_history table
# " Development environment configuration
#
# AUTHOR: jwplatta
# DATE: 2025-10-04

require_relative '../../lib/options_trader'
require 'csv'
require 'date'
require 'logger'
require 'optparse'
require 'fileutils'

class UnderlyingPriceUpdater
  include OptionsTrader::Loggable

  SPX_DATA_PATH = '/Volumes/ext_docs/options_trader/historical/indexes/SPX.csv'
  BATCH_SIZE = 100
  TARGET_UNDERLYING = 'SPX'

  def initialize(start_date: nil, end_date: nil, dry_run: false)
    @start_date = start_date
    @end_date = end_date
    @dry_run = dry_run
    @spx_prices = {}
    @spx_timestamps = {}
    @updated_count = 0
    @skipped_count = 0
    @error_count = 0
    @earliest_spx_date = nil
  end

  def update!
    logger.info("Starting underlying price update for #{TARGET_UNDERLYING} options")
    logger.info("Dry run mode: #{@dry_run}")

    validate_data_file!
    load_spx_prices!
    update_option_records!

    log_summary
  end

  private

  def validate_data_file!
    unless File.exist?(SPX_DATA_PATH)
      raise "SPX data file not found: #{SPX_DATA_PATH}"
    end

    logger.info("SPX data file found: #{SPX_DATA_PATH}")
  end

  def load_spx_prices!
    logger.info("Loading SPX price data...")

    CSV.foreach(SPX_DATA_PATH, headers: true) do |row|
      # Convert Unix millisecond timestamp to Time object (in UTC)
      timestamp_ms = row['datetime_ms'].to_i
      datetime = Time.at(timestamp_ms / 1000.0).utc

      @spx_prices[datetime] = {
        open: row['open'].to_f,
        close: row['close'].to_f,
        high: row['high'].to_f,
        low: row['low'].to_f
      }
      @spx_timestamps[datetime] = datetime
    end

    logger.info("Loaded #{@spx_prices.length} SPX price records")

    if @spx_prices.empty?
      raise "No SPX price data loaded from file"
    end

    @sorted_timestamps = @spx_prices.keys.sort
    @earliest_spx_date = @sorted_timestamps.first
    logger.info("Price data range: #{@earliest_spx_date} to #{@sorted_timestamps.last}")
  end

  def update_option_records!
    logger.info("Updating option chain history records...")

    query = OptionsTrader::OptionChainHistory.where(underlying_symbol: TARGET_UNDERLYING)
                                              .where(underlying_price: nil)

    if @earliest_spx_date
      query = query.where('valid_time >= ?', @earliest_spx_date)
      logger.info("Filtering from earliest SPX date: #{@earliest_spx_date}")
    end

    if @start_date
      start_datetime = @start_date.to_datetime.beginning_of_day
      query = query.where('valid_time >= ?', start_datetime)
      logger.info("Filtering from user start date: #{start_datetime}")
    end

    if @end_date
      end_datetime = @end_date.to_datetime.end_of_day
      query = query.where('valid_time <= ?', end_datetime)
      logger.info("Filtering to user end date: #{end_datetime}")
    end

    total_records = query.count
    logger.info("Found #{total_records} option records to process (with nil underlying_price)")

    if total_records == 0
      logger.warn("No records found to update")
      return
    end

    query.find_in_batches(batch_size: BATCH_SIZE) do |batch|
      process_batch(batch)
    end
  end

  def process_batch(options)
    logger.info("Processing batch of #{options.length} records...")

    updates = []

    options.each do |option|
      begin
        result = find_spx_price_at_time(option.valid_time)

        if result.nil?
          @skipped_count += 1
          logger.debug("No SPX price found for #{option.symbol} at #{option.valid_time}")
          next
        end

        underlying_price = result[:price]
        underlying_datetime = result[:datetime]

        updates << {
          id: option.id,
          underlying_price: underlying_price,
          symbol: option.symbol,
          underlying_datetime: underlying_datetime
        }
      rescue StandardError => e
        @error_count += 1
        logger.error("Error processing option #{option.symbol}: #{e.message}")
      end
    end

    if updates.any?
      if @dry_run
        updates.each do |update|
          logger.info("[DRY RUN] Would update #{update[:symbol]}: underlying_price = #{update[:underlying_price]} (at #{update[:underlying_datetime]})")
        end
        @updated_count += updates.length
      else
        # Use raw SQL for efficient batch updates with ON CONFLICT
        updates.each_slice(500) do |slice|
          # Build VALUES clause: (1, 100.5), (2, 101.2), ...
          values = slice.map { |u| "(#{u[:id]}, #{u[:underlying_price]})" }.join(', ')

          # Use INSERT ... ON CONFLICT to update only underlying_price
          sql = <<-SQL
            UPDATE option_chain_history
            SET underlying_price = updates.underlying_price
            FROM (VALUES #{values}) AS updates(id, underlying_price)
            WHERE option_chain_history.id = updates.id
          SQL

          ActiveRecord::Base.connection.execute(sql)
          @updated_count += slice.length
        end
        logger.debug("Batch updated #{updates.length} records")
      end
    end

    logger.info("Batch complete. Updated: #{@updated_count}, Skipped: #{@skipped_count}, Errors: #{@error_count}")
  end

  def find_spx_price_at_time(target_time)
    target_time = target_time.to_time.utc if target_time.respond_to?(:to_time)

    index = binary_search_timestamp(target_time)

    return nil if index.nil?

    timestamp = @sorted_timestamps[index]
    price_data = @spx_prices[timestamp]

    {
      price: price_data[:close],
      datetime: timestamp
    }
  end

  def binary_search_timestamp(target_time)
    left = 0
    right = @sorted_timestamps.length - 1
    result_index = nil

    while left <= right
      mid = (left + right) / 2
      mid_time = @sorted_timestamps[mid]

      if mid_time <= target_time
        result_index = mid
        left = mid + 1
      else
        right = mid - 1
      end
    end

    result_index
  end

  def log_summary
    logger.info("Underlying price update completed")
    logger.info("Records updated: #{@updated_count}")
    logger.info("Records skipped: #{@skipped_count}")
    logger.info("Errors encountered: #{@error_count}")

    if @dry_run
      logger.info("DRY RUN - No actual database changes were made")
    end
  end
end

if __FILE__ == $0
  options = {
    start_date: nil,
    end_date: nil,
    dry_run: false
  }

  OptionParser.new do |opts|
    opts.banner = "Usage: ruby scripts/backtest/update_underlying_price.rb [options]"
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

    opts.on("--dry-run", "Show what would be updated without making changes") do
      options[:dry_run] = true
    end

    opts.on("-h", "--help", "Show this help message") do
      puts opts
      exit 0
    end

    opts.separator ""
    opts.separator "Examples:"
    opts.separator "  ruby scripts/backtest/update_underlying_price.rb"
    opts.separator "  ruby scripts/backtest/update_underlying_price.rb --start-date 2023-09-26 --end-date 2023-09-27"
    opts.separator "  ruby scripts/backtest/update_underlying_price.rb --dry-run"
  end.parse!

  if options[:start_date] && options[:end_date] && options[:start_date] > options[:end_date]
    puts "Error: Start date must be before or equal to end date"
    exit 1
  end

  puts "Underlying Price Updater for Options Backtest Data"
  puts "Start Date: #{options[:start_date] || 'From earliest SPX data'}"
  puts "End Date: #{options[:end_date] || 'All data'}"
  puts "Dry Run: #{options[:dry_run]}"
  puts ""

  # Verify we're using the development environment
  current_env = ENV['RAILS_ENV'] || ENV['RACK_ENV']
  if current_env != 'development'
    puts "ERROR: This script must be run with RAILS_ENV=development and RACK_ENV=development"
    puts "Current environment: #{current_env}"
    puts ""
    puts "Usage:"
    puts "  RAILS_ENV=development RACK_ENV=development ruby scripts/backtest/update_underlying_price.rb"
    exit 1
  end

  puts "Environment: #{current_env}"
  puts "Database Configuration:"
  puts "  Database: #{ENV['DATABASE_NAME_DEV'] || 'options_trader_db'}"
  puts "  Host: #{ENV['DATABASE_HOST_DEV'] || 'localhost'}"
  puts "  Port: #{ENV['DATABASE_PORT_DEV'] || '5432'}"
  puts "  User: #{ENV['DATABASE_USER_DEV'] || 'postgres'}"
  puts ""

  updater = UnderlyingPriceUpdater.new(
    start_date: options[:start_date],
    end_date: options[:end_date],
    dry_run: options[:dry_run]
  )

  begin
    updater.update!
    puts "\nUpdate completed successfully!"
  rescue StandardError => e
    puts "\nUpdate failed: #{e.message}"
    puts e.backtrace.join("\n") if ENV['DEBUG']
    exit 1
  end
end