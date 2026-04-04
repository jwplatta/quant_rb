#!/usr/bin/env ruby
# frozen_string_literal: true

require 'date'
require 'optparse'
require_relative '../lib/options_trader'

# Default values
options = {
  start_expiration_date: (Date.today + 1).iso8601,
  valid_time: Time.now.utc.iso8601
}

# Parse command line options
OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"

  opts.on("--start-expiration-date DATE", "Start expiration date (default: today)") do |date|
    options[:start_expiration_date] = Date.parse(date).iso8601
  end

  opts.on("--valid-time TIME", "Valid time (default: now UTC)") do |time|
    options[:valid_time] = Time.parse(time).utc.iso8601
  end

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

puts "Testing SampleSpxOptionChain9DTE worker"
puts "Start expiration date: #{options[:start_expiration_date]}"
puts "Valid time: #{options[:valid_time]}"
puts "Environment: SAMPLES_FLATFILES_PATH = #{ENV['SAMPLES_FLATFILES_PATH']}"
puts ""

unless ENV['SAMPLES_FLATFILES_PATH']
  puts "ERROR: SAMPLES_FLATFILES_PATH environment variable is not set"
  puts "Please set it to the desired output directory, e.g.:"
  puts "export SAMPLES_FLATFILES_PATH=/path/to/samples"
  exit 1
end

begin
  worker = OptionsTrader::Workers::SampleSpxOptionChain9DTE.new
  worker.perform(options[:start_expiration_date], options[:valid_time])

  puts ""
  puts "Worker completed successfully!"
  puts "Check the SAMPLES_FLATFILES_PATH directory for generated CSV files."

rescue StandardError => e
  puts "ERROR: Worker failed with exception:"
  puts e.message
  puts ""
  puts "Backtrace:"
  puts e.backtrace.join("\n")
  exit 1
end