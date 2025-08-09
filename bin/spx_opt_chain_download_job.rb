#!/usr/bin/env ruby
# frozen_string_literal: true

require 'logger'
require 'clockwork'
require 'date'
require_relative '../lib/options_trader'

UNDERLYING_SYMBOL = "$SPX"
START_DATE = Date.today
END_DATE = Date.today + 30
UTC_OFFSET = '+00:00'

def market_open?
  now = Time.now.utc
  return false if now.saturday? || now.sunday?

  open = Time.new(now.year, now.month, now.day, 13, 30, 0, UTC_OFFSET)
  close = Time.new(now.year, now.month, now.day, 20, 15, 0, UTC_OFFSET)
  now >= open && now <= close
end

def generate_business_days(start_date, end_date)
  business_days = []
  current_date = start_date

  while current_date <= end_date
    unless current_date.wday == 0 || current_date.wday == 6
      business_days << current_date
    end
    current_date += 1
  end

  business_days
end

module Clockwork
  logger = Logger.new(STDOUT)
  logger.level = Logger::DEBUG

  every(5.minutes, 'download_SPX_options_chain.job') do |job, _|
    valid_time = Time.now.utc
    if market_open?
      logger.info "Running job: #{job} at #{valid_time}"
      business_days = generate_business_days(START_DATE, END_DATE)
      business_days.each do |business_day|
        OptionsTrader::Workers::SampleOptionsChain.perform_async(
          UNDERLYING_SYMBOL,
          business_day.iso8601,
          valid_time.iso8601,
        )
      end
    else
      logger.info "Market is closed. Skipping job: #{job} at #{valid_time}"
      now = Time.now.utc
      next_day = Time.new(now.year, now.month, now.day, 13, 30, 0, UTC_OFFSET)
      next_open = case now.wday
        when 5 # friday
          next_day + 3 * 86400 # 3 days later
        when 6 # saturday
          next_day + 2 * 86400 # 2 days later
        else # sunday or weekday
          next_day + 1 * 86400 # 1 day later
        end

      sleep_seconds = [next_open - Time.now.utc, 0].max
      logger.info "Sleeping for #{sleep_seconds.to_i} seconds until next market open at #{next_open}"
      sleep(sleep_seconds)
    end
  rescue StandardError => e
    logger.error "Error in job #{job}: #{e.message}"
    logger.debug e.backtrace.join("\n")
  end
end
