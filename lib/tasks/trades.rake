# frozen_string_literal: true

require 'dotenv'
require_relative '../platypi'
require_relative '../platypi/bots/spx_weekly_trade'

Dotenv.load

namespace :trades do
  desc 'Run SPX Weekly Trade Bot'
  task :spx_weekly_trade => :environment do
    puts "Starting SPX Weekly Trade Bot..."

    begin
      bot = SPXWeeklyTrade.new
      bot.run
    rescue => e
      puts "Error running SPX Weekly Trade Bot: #{e.message}"
      puts e.backtrace.join("\n")
      exit 1
    end
  end
end