#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../lib/options_trader'
require 'date'
require 'logger'
require 'pry'
require 'csv'

EXPIRATION_DATE = '2025-06-13'
VALID_TIME = '2025-06-10 14:20:00'
UNDERLYING_SYMBOL = '$SPX'

logger = Logger.new($stdout)
logger.level = Logger::DEBUG

puts "Building synthetic option chain for #{UNDERLYING_SYMBOL}"
puts "Expiration Date: #{EXPIRATION_DATE}"
puts "Valid Time: #{VALID_TIME}"
puts "-" * 80

# Step 1: Create HistoricalSnapshot service to fetch historical option chain data
snapshot_service = OptionsTrader::Services::HistoricalSnapshot.new(
  valid_time: Time.parse(VALID_TIME)
)

# Step 2: Fetch the option chain with enriched features (vix9d, vvix)
# These features are required by the Greek Forge delta prediction model
puts "\nFetching historical option chain with features..."
option_chain = snapshot_service.get_option_chain(
  UNDERLYING_SYMBOL,
  expiration_date: EXPIRATION_DATE,
  window: 5,
  features: {
    vix9d: '$VIX9D',
    vvix: '$VVIX'
  }
)

puts "Fetched option chain:"
puts "  Underlying Price: $#{option_chain.underlying_price}"
puts "  Call Options: #{option_chain.call_opts.size}"
puts "  Put Options: #{option_chain.put_opts.size}"

# Step 3: Initialize Greek Forge predictor
puts "\nInitializing Greek Forge predictor..."
predictor = OptionsTrader::Predictors::GreekForge.new(
  host: ENV.fetch('GREEK_FORGE_HOST', 'localhost'),
  port: ENV.fetch('GREEK_FORGE_PORT', 8000).to_i,
  scheme: ENV.fetch('GREEK_FORGE_SCHEME', 'http')
)

# Check health of Greek Forge service
begin
  health_response = predictor.health
  puts "Greek Forge service is healthy: #{health_response}"
rescue OptionsTrader::Predictors::GreekForge::ConnectionError => e
  puts "ERROR: Cannot connect to Greek Forge service: #{e.message}"
  puts "Please ensure the Greek Forge service is running on #{predictor.scheme}://#{predictor.host}:#{predictor.port}"
  exit 1
end

# Step 4: Initialize DeltaEnricher service
puts "\nInitializing Delta Enricher..."
delta_enricher = OptionsTrader::Services::DeltaEnricher.new(predictor: predictor)

# Step 5: Enrich the option chain with delta predictions
puts "\nEnriching option chain with delta predictions..."
begin
  enriched_chain = delta_enricher.enrich(option_chain)
  puts "Successfully enriched option chain with deltas!"
rescue OptionsTrader::Services::DeltaEnricher::Error => e
  puts "ERROR: Failed to enrich option chain: #{e.message}"
  exit 1
end


binding.pry
# Step 6: Display results
puts "\n" + "=" * 80
puts "ENRICHED OPTION CHAIN RESULTS"
puts "=" * 80

puts "\nUnderlying: #{enriched_chain.symbol} @ $#{enriched_chain.underlying_price}"

puts "\nCALL OPTIONS (sample - first 10):"
puts "Strike".ljust(10) + "Mark".ljust(10) + "Delta".ljust(10) + "DTE".ljust(6) + "Moneyness".ljust(12) + "VIX9D".ljust(8) + "VVIX"
puts "-" * 80
enriched_chain.call_opts.first(10).each do |opt|
  vix9d = opt.respond_to?(:vix9d) ? opt.vix9d&.round(2) : 'N/A'
  vvix = opt.respond_to?(:vvix) ? opt.vvix&.round(2) : 'N/A'
  moneyness = opt.has_feature?(:moneyness) ? opt.moneyness&.round(4) : (opt.underlying_price / opt.strike.to_f).round(4)

  puts "#{opt.strike}".ljust(10) +
       "#{opt.mark&.round(2)}".ljust(10) +
       "#{opt.delta&.round(4)}".ljust(10) +
       "#{opt.days_to_expiration}".ljust(6) +
       "#{moneyness}".ljust(12) +
       "#{vix9d}".ljust(8) +
       "#{vvix}"
end

puts "\nPUT OPTIONS (sample - first 10):"
puts "Strike".ljust(10) + "Mark".ljust(10) + "Delta".ljust(10) + "DTE".ljust(6) + "Moneyness".ljust(12) + "VIX9D".ljust(8) + "VVIX"
puts "-" * 80
enriched_chain.put_opts.first(10).each do |opt|
  vix9d = opt.respond_to?(:vix9d) ? opt.vix9d&.round(2) : 'N/A'
  vvix = opt.respond_to?(:vvix) ? opt.vvix&.round(2) : 'N/A'
  moneyness = opt.has_feature?(:moneyness) ? opt.moneyness&.round(4) : (opt.strike / opt.underlying_price.to_f).round(4)

  puts "#{opt.strike}".ljust(10) +
       "#{opt.mark&.round(2)}".ljust(10) +
       "#{opt.delta&.round(4)}".ljust(10) +
       "#{opt.days_to_expiration}".ljust(6) +
       "#{moneyness}".ljust(12) +
       "#{vix9d}".ljust(8) +
       "#{vvix}"
end

puts "\n" + "=" * 80
puts "SUMMARY STATISTICS"
puts "=" * 80

# Calculate some statistics
call_deltas = enriched_chain.call_opts.map(&:delta).compact
put_deltas = enriched_chain.put_opts.map(&:delta).compact

if call_deltas.any?
  puts "\nCall Options:"
  puts "  Total: #{enriched_chain.call_opts.size}"
  puts "  With Deltas: #{call_deltas.size}"
  puts "  Delta Range: #{call_deltas.min.round(4)} to #{call_deltas.max.round(4)}"
  puts "  Average Delta: #{(call_deltas.sum / call_deltas.size).round(4)}"
end

if put_deltas.any?
  puts "\nPut Options:"
  puts "  Total: #{enriched_chain.put_opts.size}"
  puts "  With Deltas: #{put_deltas.size}"
  puts "  Delta Range: #{put_deltas.min.round(4)} to #{put_deltas.max.round(4)}"
  puts "  Average Delta: #{(put_deltas.sum / put_deltas.size).round(4)}"
end

puts "\n" + "=" * 80
puts "Dropping into REPL for interactive exploration..."
puts "Available variables:"
puts "  - enriched_chain: The complete option chain with delta predictions"
puts "  - option_chain: The original option chain without deltas"
puts "  - delta_enricher: The DeltaEnricher service instance"
puts "  - predictor: The GreekForge predictor instance"
puts "  - snapshot_service: The HistoricalSnapshot service instance"
puts "=" * 80


csv_file = "enriched_option_chain_#{Time.now.strftime('%Y%m%d_%H%M%S')}.csv"
headers = %w[call_opt_mark call_opt_delta call_opt_moneyness strike put_opt_mark put_opt_delta put_opt_moneyness]

# Group options by numeric strike for reliable matching
calls_by_strike = enriched_chain.call_opts.group_by { |o| o.strike.to_f }
puts_by_strike = enriched_chain.put_opts.group_by { |o| o.strike.to_f }

all_strikes = (calls_by_strike.keys + puts_by_strike.keys).uniq.sort

CSV.open(csv_file, 'w', write_headers: true, headers: headers) do |csv|
  all_strikes.each do |strike_key|
    call = calls_by_strike[strike_key]&.first
    put  = puts_by_strike[strike_key]&.first

    call_mark = call&.mark&.round(4)
    call_delta = call&.delta&.round(4)
    call_moneyness =
      if call
        call.has_feature?(:moneyness) ? call.moneyness&.round(4) : (call.underlying_price.to_f / call.strike.to_f).round(4)
      end

    put_mark = put&.mark&.round(4)
    put_delta = put&.delta&.round(4)
    put_moneyness =
      if put
        put.has_feature?(:moneyness) ? put.moneyness&.round(4) : (put.strike.to_f / put.underlying_price.to_f).round(4)
      end

    csv << [
      call_mark,
      call_delta,
      call_moneyness,
      strike_key,
      put_mark,
      put_delta,
      put_moneyness
    ]
  end
end

puts "Wrote enriched option chain CSV to: #{csv_file}"