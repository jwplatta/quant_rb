#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'date'
require 'logger'

require_relative '../lib/options_trader'

class SpxOptionChainDownloader
  include OptionsTrader::Schwab

  attr_reader :logger, :time_increment_minutes

  def initialize(time_increment_minutes: 5)
    @time_increment_minutes = time_increment_minutes
    @logger = Logger.new(STDOUT)
    @logger.level = Logger::INFO
    @logger.formatter = proc do |severity, datetime, progname, msg|
      "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} [#{severity}] #{msg}\n"
    end
    require_relative '../config/environment'
  rescue StandardError => e
    @logger.error "Failed to load environment: #{e.message}"
    @logger.error e.backtrace.join("\n")
    exit(1)
  end

  def run(start_date: Date.today, end_date: Date.today)
    logger.info "Starting SPX option chain download from #{start_date} to #{end_date}"

    current_time = DateTime.now
    start_of_trading = DateTime.new(
      current_time.year, current_time.month, current_time.day, 8, 30, 0, current_time.zone
    )
    end_of_trading = DateTime.new(
      current_time.year,
      current_time.month,
      current_time.day, 13, 45, 0, current_time.zone
    )

    if current_time < start_of_trading
      logger.info "Current time #{current_time.strftime('%H:%M')} CST is before #{start_of_trading.strftime('%H:%M')} CST. Waiting until trading starts."
      sleep((start_of_trading - current_time).to_i)
    elsif current_time > end_of_trading
      logger.info "Current time #{current_time.strftime('%H:%M')} CST is after #{end_of_trading.strftime('%H:%M')} CST. Exiting."
      exit
    end

    business_days = generate_business_days(start_date, end_date)
    logger.info "Downloading option chains for #{business_days.length} business days"

    loop do
      time_bucket = calculate_time_bucket(Time.current)
      logger.info "Starting download cycle for time bucket: #{time_bucket}"

      business_days.each do |exp_date|
        download_option_chain_for_date(exp_date, time_bucket)
      end

      # Sleep until next time bucket
      next_bucket = time_bucket + (time_increment_minutes * 60)
      sleep_duration = [(next_bucket - Time.current).to_i, 0].max
      logger.info "Completed download cycle, sleeping #{sleep_duration} seconds until next bucket at #{next_bucket}"
      sleep(sleep_duration) if sleep_duration > 0
    end
  end

  private

  def generate_business_days(start_date, end_date)
    business_days = []
    current_date = start_date

    while current_date <= end_date
      # Skip weekends (Saturday = 6, Sunday = 0)
      unless current_date.wday == 0 || current_date.wday == 6
        business_days << current_date
      end
      current_date += 1
    end

    business_days
  end

  def download_option_chain_for_date(expiration_date, time_bucket)
    logger.info "Downloading option chain for expiration date: #{expiration_date}"

    begin
      opt_chain = option_chain(
        '$SPX',
        contract_type: 'ALL',
        to_date: expiration_date,
        from_date: expiration_date,
        strike_range: 'ALL'
      )

      if opt_chain.nil?
        logger.warn "No option chain returned for #{expiration_date}"
        return
      end

      underlying_price = opt_chain.underlying_price

      # Prepare batch data for all options
      option_records = []

      # Add call options to batch
      opt_chain.call_opts.each do |opt|
        option_records << build_option_record(opt, time_bucket, underlying_price)
      end

      # Add put options to batch
      opt_chain.put_opts.each do |opt|
        option_records << build_option_record(opt, time_bucket, underlying_price)
      end

      # Bulk insert all options at once
      if option_records.any?
        OptionsTrader::OptionChainHistory.insert_all(option_records)
        logger.info "Batch saved #{opt_chain.call_opts.length} calls and #{opt_chain.put_opts.length} puts for #{expiration_date}"
      end

    rescue StandardError => e
      logger.error "Failed to download option chain for #{expiration_date}: #{e.message}"
      logger.error e.backtrace.join("\n")
    end
  end

  def build_option_record(option, time_bucket, underlying_price)
    {
      symbol: option.symbol,
      root_symbol: option.option_root,
      underlying_symbol: option.underlying_symbol,
      expiration_date: option.expiration_date,
      strike: option.strike,
      contract_type: option.put_call,
      bid: option.bid,
      ask: option.ask,
      mark: option.mark,
      last_price: option.last,
      underlying_price: underlying_price,
      delta: round_to_2_decimal(option.delta),
      theta: round_to_2_decimal(option.theta),
      vega: round_to_2_decimal(option.vega),
      gamma: round_to_2_decimal(option.gamma),
      rho: round_to_2_decimal(option.rho),
      open_interest: option.open_interest,
      volume: option.total_volume,
      bid_size: option.bid_size,
      ask_size: option.ask_size,
      option_root: option.option_root,
      expiration_type: option.expiration_type,
      intrinsic_value: option.intrinsic_value,
      extrinsic_value: option.extrinsic_value,
      time_value: option.time_value,
      volatility: round_to_2_decimal(option.volatility),
      high_52_week: option.high_52_week,
      low_52_week: option.low_52_week,
      high_price: option.high_price,
      low_price: option.low_price,
      open_price: option.open_price,
      close_price: option.close_price,
      valid_time: time_bucket,
      transaction_time: Time.current
    }
  end

  def calculate_time_bucket(timestamp)
    # Round timestamp to the nearest time increment boundary
    # e.g., for 5-minute buckets: 10:03:42 -> 10:00:00, 10:07:15 -> 10:05:00
    minutes = timestamp.min
    rounded_minutes = (minutes / time_increment_minutes) * time_increment_minutes

    Time.new(
      timestamp.year,
      timestamp.month,
      timestamp.day,
      timestamp.hour,
      rounded_minutes,
      0,
      timestamp.zone
    )
  end

  def round_to_2_decimal(value)
    return nil if value.nil?
    value.round(2)
  end
end

if __FILE__ == $0
  # Parse command line arguments for time increment (default: 5 minutes)
  time_increment = ARGV[0]&.to_i || 5

  downloader = SpxOptionChainDownloader.new(time_increment_minutes: time_increment)

  start_date = Date.today
  end_date = Date.today + 15

  downloader.run(start_date: start_date, end_date: end_date)
end
