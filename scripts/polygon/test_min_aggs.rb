#!/usr/bin/env ruby

require_relative '../../lib/options_trader'
require 'pry'
require 'date'

puts "Testing Polygon minute aggregates..."

begin
  local_dir = ENV["POLYGON_FILES_PATH"]
  client = OptionsTrader::DataProviders::Polygon::Client.instance

  test_date = Date.new(2023, 9, 29)

  puts "Loading minute aggregates from local files for #{test_date}..."

  # Create a specific datetime for testing (e.g., 2:30 PM ET)
  test_datetime = DateTime.new(test_date.year, test_date.month, test_date.day, 14, 30, 0, '-5')

  # Test 1: Get all options (all types, all expirations)
  puts "\n=== Test 1: All options ==="
  options_chain_all = client.get_option_chain(
    "SPXW",
    datetime: test_datetime,
    agg_size: "min",
    local_dir: local_dir
  )

  puts "Found options chain for #{options_chain_all.symbol}"
  puts "Calls: #{options_chain_all.call_opts.length}"
  puts "Puts: #{options_chain_all.put_opts.length}"

  # Test 2: Filter for specific expiration (October 6, 2023)
  puts "\n=== Test 2: Specific expiration (Oct 6, 2023) ==="
  target_expiration = Date.new(2023, 10, 6)

  options_chain_filtered = client.get_option_chain(
    "SPXW",
    datetime: test_datetime,
    agg_size: "min",
    local_dir: local_dir,
    to_date: target_expiration
  )

  # Test 3: Filter for calls only
  puts "\n=== Test 3: Calls only ==="
  options_chain_calls = client.get_option_chain(
    "SPXW",
    datetime: test_datetime,
    agg_size: "min",
    local_dir: local_dir,
    to_date: target_expiration,
    contract_type: 'CALL'
  )

  puts "Found options chain for #{options_chain_calls.symbol} (calls only)"
  puts "Calls: #{options_chain_calls.call_opts.length}"
  puts "Puts: #{options_chain_calls.put_opts.length}"

  # Test 4: Filter using days_to_expiration (7 days out)
  puts "\n=== Test 4: 7 days to expiration ==="
  options_chain_dte = client.get_option_chain(
    "SPXW",
    datetime: test_datetime,
    agg_size: "min",
    local_dir: local_dir,
    days_to_expiration: 7,
    contract_type: 'PUT'
  )

  puts "Found options chain for #{options_chain_dte.symbol} (7 DTE puts only)"
  puts "Calls: #{options_chain_dte.call_opts.length}"
  puts "Puts: #{options_chain_dte.put_opts.length}"

  # Test 5: Show sample data and available expiration dates
  puts "\n=== Test 5: Sample data and available expirations ==="
  puts "Sample from filtered chain (#{target_expiration}):"
  puts "Calls: #{options_chain_filtered.call_opts.length}"
  puts "Puts: #{options_chain_filtered.put_opts.length}"

  if options_chain_filtered.call_opts.any?
    puts "\nFirst few calls:"
    options_chain_filtered.call_opts.first(3).each do |call|
      puts "  #{call.symbol} - Strike: #{call.strike}, Mark: #{call.mark}, Volume: #{call.total_volume}, Exp: #{call.expiration_date}"
    end
  end

  # Show unique expiration dates from all options
  all_expirations = (options_chain_all.call_opts + options_chain_all.put_opts)
                   .map(&:expiration_date)
                   .uniq
                   .sort

  puts "\nAvailable expiration dates: #{all_expirations.join(', ')}"

  binding.pry
rescue StandardError => e
  puts "Error: #{e.message}"
  puts e.backtrace if ENV['DEBUG']
  exit 1
end

puts "\nTest completed successfully!"