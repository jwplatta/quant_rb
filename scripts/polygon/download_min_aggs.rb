#!/usr/bin/env ruby

require "pry"
require "date"
require_relative "../../config/environment"
require_relative "../../lib/options_trader"
require 'aws-sdk-s3'

if ARGV.length != 2
  puts "Usage: #{$0} <start_date> <end_date>"
  puts "Date format: YYYY-MM-DD"
  puts "Example: #{$0} 2023-01-01 2023-12-31"
  exit 1
end

begin
  start_date = Date.parse(ARGV[0])
  end_date = Date.parse(ARGV[1])
rescue ArgumentError => e
  puts "Error parsing dates: #{e.message}"
  puts "Please use YYYY-MM-DD format"
  exit 1
end

if start_date > end_date
  puts "Error: Start date must be before or equal to end date"
  exit 1
end

Aws.config[:region] = 'us-west-2'
dir = ENV["POLYGON_FILES_PATH"]

client = OptionsTrader::DataProviders::Polygon::Client.instance

puts "Downloading aggregates from #{start_date} to #{end_date}"

(start_date..end_date).each do |date|
  puts "Downloading aggs for #{date} to #{dir}"

  begin
    client.download_min_aggs(date, local_dir: dir)
  rescue StandardError => e
    puts "Error downloading aggs for #{date}: #{e.message}"
  end
end

puts "Done"