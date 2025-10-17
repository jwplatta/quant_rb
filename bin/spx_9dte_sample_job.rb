#!/usr/bin/env ruby
# frozen_string_literal: true

require 'logger'
require 'clockwork'
require 'date'
require_relative '../lib/options_trader'

UTC_OFFSET = '+00:00'

def market_hours_active?
  now = Time.now.utc
  return false if now.saturday? || now.sunday?

  market_open = Time.new(now.year, now.month, now.day, 13, 30, 0, UTC_OFFSET)
  market_close_plus_15 = Time.new(now.year, now.month, now.day, 20, 30, 0, UTC_OFFSET) # 20:15 + 15 minutes

  now >= market_open && now <= market_close_plus_15
end

def time_to_next_run
  now = Time.now.utc

  if now.saturday? || now.sunday?
    days_until_monday = case now.wday
    when 6 # Saturday
      2
    when 0 # Sunday
      1
    end
    next_monday_open = Time.new(now.year, now.month, now.day, 13, 30, 0, UTC_OFFSET) + (days_until_monday * 86400)
    return next_monday_open - now
  end

  # If it's a weekday but outside market hours
  unless market_hours_active?
    today_open = Time.new(now.year, now.month, now.day, 13, 30, 0, UTC_OFFSET)
    if now < today_open
      return today_open - now
    else
      next_day = case now.wday
      when 5 # Friday
        now + (3 * 86400) # Monday
      else
        now + 86400 # Next day
      end
      next_open = Time.new(next_day.year, next_day.month, next_day.day, 13, 30, 0, UTC_OFFSET)
      return next_open - now
    end
  end

  0 # Run immediately if we're in active hours
end

module Clockwork
  logger = Logger.new(STDOUT)
  logger.level = Logger::DEBUG

  every(30.minutes, 'sample_spx_9dte_option_chain.job') do |job, _|
    valid_time = Time.now.utc

    if market_hours_active?
      logger.info "Running job: #{job} at #{valid_time}"

      start_expiration_date = Date.today

      begin
        OptionsTrader::Workers::SampleSpxOptionChain9DTE.perform_async(
          start_expiration_date.iso8601,
          valid_time.iso8601
        )

        logger.info "Enqueued SampleSpxOptionChain9DTE job for #{start_expiration_date} at #{valid_time}"
      rescue StandardError => e
        logger.error "Failed to enqueue SampleSpxOptionChain9DTE job: #{e.message}"
        logger.error e.backtrace.join("\n")
      end
    else
      logger.info "Outside market hours. Skipping job: #{job} at #{valid_time}"

      sleep_seconds = time_to_next_run.to_i
      if sleep_seconds > 0
        next_run_time = Time.now.utc + sleep_seconds
        logger.info "Sleeping for #{sleep_seconds} seconds until next run at #{next_run_time}"
        sleep(sleep_seconds)
      end
    end
  rescue StandardError => e
    logger.error "Error in job #{job}: #{e.message}"
    logger.error e.backtrace.join("\n")
  end
end
