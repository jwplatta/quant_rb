# frozen_string_literal: true

require 'dotenv'
require_relative '../platypi'
require_relative '../platypi/bots/spx_weekly'

Dotenv.load

namespace :trading do
  desc 'Run SPX Weekly Trade Bot'
  task :spx_weekly_trade => :environment do
    puts "Starting SPX Weekly Trade Bot..."

    begin
      # Initialize the SPX Weekly bot in preview mode
      bot = Platypi::SPXWeekly.new(mode: :preview)

      # Set up signal handling for graceful shutdown
      Signal.trap('INT') do
        puts "\nReceived interrupt signal. Stopping bot..."
        bot.stop
        exit 0
      end

      Signal.trap('TERM') do
        puts "\nReceived termination signal. Stopping bot..."
        bot.stop
        exit 0
      end

      # Run the bot
      bot.run
    rescue => e
      puts "Error running SPX Weekly Trade Bot: #{e.message}"
      puts e.backtrace.join("\n")
      exit 1
    end
  end
end