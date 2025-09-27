#!/usr/bin/env ruby

require "pry"
require "date"
require_relative "../../config/environment"
require_relative "../../lib/options_trader"
require 'aws-sdk-s3'

Aws.config[:region] = 'us-west-2'
dir = ENV["POLYGON_FILES_PATH"]

client = OptionsTrader::DataProviders::Polygon::Client.instance

years = [2023, 2024, 2025]

years.each do |year|
  (1..12).each do |month|
    (1..31).each do |day|
      agg_month = Date.new(year, month, day) rescue nil
      puts "Downloading aggs for #{agg_month} to #{dir}"
      begin
        client.download_min_aggs(agg_month, local_dir: dir)
      rescue StandardError => e
        puts "Error downloading aggs for #{agg_month}: #{e.message}"
      end
    end
  end
end

puts "Done"