#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'date'
require 'logger'
require 'pry'

require_relative '../lib/options_trader'

class SpxOptionChainTestDownloader
  include OptionsTrader::Schwab

  attr_reader :logger

  def initialize
    @logger = Logger.new(STDOUT)
    @logger.level = Logger::INFO
    @logger.formatter = proc do |severity, datetime, progname, msg|
      "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} [#{severity}] #{msg}\n"
    end
    # Database connection handled by config/environment.rb
  end

  def test_single_download(expiration_date = Date.new(2025, 8, 5))
    logger.info "Testing SPX option chain download for expiration date: #{expiration_date}"

    current_time = Time.current

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
        return false
      end

      underlying_price = opt_chain.underlying_price
      logger.info "Underlying SPX price: #{underlying_price}"

      # Test saving one call and one put option
      if opt_chain.call_opts.any?
        test_opt = opt_chain.call_opts.first
        save_option_to_history(test_opt, current_time, underlying_price)
        logger.info "Successfully saved test call option: #{test_opt.symbol}"
      end

      if opt_chain.put_opts.any?
        test_opt = opt_chain.put_opts.first
        save_option_to_history(test_opt, current_time, underlying_price)
        logger.info "Successfully saved test put option: #{test_opt.symbol}"
      end

      logger.info "Test completed successfully!"
      logger.info "Total available: #{opt_chain.call_opts.length} calls, #{opt_chain.put_opts.length} puts"

      true
    rescue StandardError => e
      logger.error "Test failed: #{e.message}"
      logger.error e.backtrace.join("\n")
      false
    end
  end

  private

  def save_option_to_history(option, valid_time, underlying_price)
    OptionsTrader::OptionChainHistory.create!(
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
      valid_time: valid_time,
      transaction_time: Time.current
    )
  end

  def round_to_2_decimal(value)
    return nil if value.nil?
    value.round(2)
  end
end

if __FILE__ == $0
  downloader = SpxOptionChainTestDownloader.new

  test_date = ARGV[0] ? Date.parse(ARGV[0]) : Date.new(2025, 8, 4)

  success = downloader.test_single_download(test_date)
  exit(success ? 0 : 1)
end