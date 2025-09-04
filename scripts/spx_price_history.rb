#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../lib/options_trader'
require 'date'
require 'logger'
require 'pry'

class SPXPriceHistory
  include OptionsTrader::Schwab

  def initialize
    @logger = Logger.new(STDOUT)
    @logger.level = Logger::INFO
    @logger.formatter = proc do |severity, datetime, progname, msg|
      "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} [#{severity}] #{msg}\n"
    end
  end

  def download(start_date, end_date)
    @logger.info("Downloading SPX options data from #{start_date} to #{end_date}")

    price_hist = price_history_every_minute('$SPX', start_date, end_date)

    binding.pry
  end
end

if __FILE__ == $0
  start_date = ARGV[0] ? Date.parse(ARGV[0]) : Date.new(2025, 8, 1)
  end_date = ARGV[1] ? Date.parse(ARGV[1]) : Date.new(2025, 8, 29)

  history = SPXPriceHistory.new
  success = history.download(start_date, end_date)

  exit(success ? 0 : 1)
end
