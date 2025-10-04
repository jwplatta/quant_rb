#!/usr/bin/env ruby

require 'pry'
require 'date'
require_relative '../config/environment'
require_relative '../lib/options_trader'
require_relative '../lib/options_trader/utils/delta_interpolator'
require_relative '../lib/options_trader/utils/pchip_interpolator'
require_relative '../lib/options_trader/charts/line_graph'

######################
### UTIL FUNCTIONS ###
######################

def calc_moneyness(spot_price, strike_price)
  spot_price / strike_price.to_f
end

def build_options_chain_from_records(records, underlying_symbol)
  call_opts = []
  put_opts = []
  records.each do |record|
    if record.contract_type == "CALL"
      call_opts << OptionsTrader::DataObjects::Option.new(
        symbol: record.symbol,
        underlying_symbol: underlying_symbol,
        strike: record.strike,
        put_call: record.contract_type,
        mark: record.mark,
        underlying_price: record.underlying_price,
        expiration_date: record.expiration_date,
        days_to_expiration: (Date.parse(record.expiration_date.to_s) - Date.parse(record.valid_time.to_s)).to_i,
        delta: record.delta,
        gamma: record.gamma,
        theta: record.theta,
        vega: record.vega,
        rho: record.rho,
        open_interest: record.open_interest,
        total_volume: record.volume,
        option_root: 'SPXW',
        in_the_money: record.strike < record.underlying_price
      )
    else
      put_opts << OptionsTrader::DataObjects::Option.new(
        symbol: record.symbol,
        underlying_symbol: underlying_symbol,
        strike: record.strike,
        put_call: record.contract_type,
        mark: record.mark,
        underlying_price: record.underlying_price,
        expiration_date: record.expiration_date,
        days_to_expiration: (Date.parse(record.expiration_date.to_s) - Date.parse(record.valid_time.to_s)).to_i,
        delta: record.delta,
        gamma: record.gamma,
        theta: record.theta,
        vega: record.vega,
        rho: record.rho,
        open_interest: record.open_interest,
        total_volume: record.volume,
        option_root: 'SPXW',
        in_the_money: record.strike > record.underlying_price
      )
    end
  end

  OptionsTrader::DataObjects::OptionsChain.new(
    symbol: 'SPX',
    underlying_price: records.first&.underlying_price,
    call_opts: call_opts,
    put_opts: put_opts
  )
end

def calculate_delta_from_price_history(current_price, previous_price, current_spot, previous_spot, contract_type = 'CALL')
  spot_change = current_spot - previous_spot
  price_change = current_price - previous_price

  return 0.0 if spot_change.abs < 0.000001  # Avoid division by tiny numbers

  delta = price_change / spot_change

  if delta.abs > 1.0 && contract_type == 'CALL' # Delta can't exceed 1.0 for single options
    1.0
  elsif delta.abs > 1.0 && contract_type == 'PUT' # Delta can't be less than -1.0 for single options
    -1.0
  else
    delta
  end
end

def get_straddle_price(option_chain)
  call_atm = option_chain.call_opts.min_by { |opt| (opt.strike - option_chain.underlying_price).abs }
  put_atm = option_chain.put_opts.min_by { |opt| (opt.strike - option_chain.underlying_price).abs }

  return nil if call_atm.nil? || put_atm.nil?

  call_atm.mark + put_atm.mark
end

def get_nearest_strike(option_chain, target_strike, volume_threshold = 0)
  call_opts = if volume_threshold > 0
    option_chain.call_opts.select { |opt| opt.total_volume >= volume_threshold }
  else
    option_chain.call_opts
  end

  put_opts = if volume_threshold > 0
    option_chain.put_opts.select { |opt| opt.total_volume >= volume_threshold }
  else
    option_chain.put_opts
  end

  all_strikes = (call_opts.map { |opt| opt.strike } + put_opts.map { |opt| opt.strike }).uniq
  all_strikes.min_by { |strike| (strike - target_strike).abs }
end

def max_strike(option_chain)
  all_strikes = (option_chain.call_opts.map(&:strike) + option_chain.put_opts.map(&:strike)).uniq
  all_strikes.max
end

def min_strike(option_chain)
  all_strikes = (option_chain.call_opts.map(&:strike) + option_chain.put_opts.map(&:strike)).uniq
  all_strikes.min
end

def atm_strike(option_chain, put_call = 'CALL')
  all_strikes = if put_call == 'CALL'
    option_chain.call_opts.map(&:strike)
  else
    option_chain.put_opts.map(&:strike)
  end
  all_strikes.min_by { |strike| (strike - option_chain.underlying_price).abs }
end

####################
### START SCRIPT ###
####################
expiration_date = '2025-08-18'
test_expiry = Date.parse(expiration_date)
underlying_symbol = '$SPX'
timestamps = [
  DateTime.parse('2025-08-11 14:04:18'),
  DateTime.parse('2025-08-11 14:19:18'),
  # DateTime.parse('2025-08-11 14:24:18'),
  # DateTime.parse('2025-08-11 14:29:18'),
  DateTime.parse('2025-08-11 14:34:18'),
  # DateTime.parse('2025-08-11 14:39:18'),
  # DateTime.parse('2025-08-11 14:44:18'),
  DateTime.parse('2025-08-11 14:49:18'),
  # DateTime.parse('2025-08-11 14:54:18'),
  # DateTime.parse('2025-08-11 14:59:18'),
  DateTime.parse('2025-08-11 15:04:18')
].sort

option_chains = {}

timestamps.each do |ts|
  puts "Building option chain at #{ts}"

  records = OptionsTrader::OptionChainHistory
    .where(expiration_date: expiration_date)
    .where(valid_time: ts)
    .where("volume > 0")

  opts_chain = build_options_chain_from_records(records, underlying_symbol)

  option_chains[ts] = {
    'chain' => opts_chain,
    'spot_price' => records.first&.underlying_price
  }
end

start_timestamp_index = 3
timestamp_cnt = 3

# Get the last option chain for analysis
last_timestamp = timestamps.last
last_chain_data = option_chains[last_timestamp]
current_option_chain = last_chain_data['chain']
current_spot = last_chain_data['spot_price']

curr_max_strike = max_strike(current_option_chain)
curr_min_strike = min_strike(current_option_chain)

puts "\n=== DELTA INTERPOLATION ANALYSIS ==="
puts "Processing option chain at: #{last_timestamp}"
puts "Current spot price: #{current_spot}"

# Step 1: Calculate 1σ move using ATM straddle price
current_1sigma_move = get_straddle_price(current_option_chain)
puts "ATM straddle price (1-sig move): #{current_1sigma_move}"

# Step 2: Calculate target strikes for CALL options (both ITM and OTM)
# ITM strikes (above current spot)
strike_1sigma_call_itm = current_spot + current_1sigma_move
strike_2sigma_call_itm = current_spot + (2 * current_1sigma_move)
strike_3sigma_call_itm = current_spot + (3 * current_1sigma_move)

# OTM strikes (below current spot)
strike_1sigma_call_otm = current_spot - current_1sigma_move
strike_2sigma_call_otm = current_spot - (2 * current_1sigma_move)
strike_3sigma_call_otm = current_spot - (3 * current_1sigma_move)

puts "\nTarget strikes for CALL options:"
puts "ITM (above spot):"
puts "  1-sig ITM call strike: #{strike_1sigma_call_itm}"
puts "  2-sig ITM call strike: #{strike_2sigma_call_itm}"
puts "  3-sig ITM call strike: #{strike_3sigma_call_itm}"
puts "OTM (below spot):"
puts "  1-sig OTM call strike: #{strike_1sigma_call_otm}"
puts "  2-sig OTM call strike: #{strike_2sigma_call_otm}"
puts "  3-sig OTM call strike: #{strike_3sigma_call_otm}"

# Find actual strikes closest to target strikes
key_call_strikes = [
  # ATM strike
  atm_strike(current_option_chain, 'CALL'),
  # ITM strikes
  get_nearest_strike(current_option_chain, strike_1sigma_call_itm, 50),
  get_nearest_strike(current_option_chain, strike_2sigma_call_itm, 50),
  get_nearest_strike(current_option_chain, strike_3sigma_call_itm, 50),
  # OTM strikes
  get_nearest_strike(current_option_chain, strike_1sigma_call_otm, 50),
  get_nearest_strike(current_option_chain, strike_2sigma_call_otm, 50),
  get_nearest_strike(current_option_chain, strike_3sigma_call_otm, 50)
].uniq


# NOTE: maybe find key strikes near the standard moves with the highest volume?
# current_option_chain.call_opts.sort_by(&:strike).each do |call_opt|
#   puts "Call strike: #{call_opt.strike.to_f}, total volume: #{call_opt.total_volume}"
# end

puts "\nActual key CALL strikes to analyze:"
key_call_strikes.each do |strike|
  puts "  #{strike}"
end

# Step 3: Calculate averaged deltas for key strikes over last 4 samples
# We need at least 4 timestamps for this calculation
if timestamps.length >= 3
  last_4_timestamps = timestamps.last(4)
  puts "\nCalculating averaged deltas over last 4 samples:"
  last_4_timestamps.each { |ts| puts "  #{ts}" }

  strike_deltas = {}

  key_call_strikes.each do |target_strike|
    deltas = []

    # Calculate delta for each of the last 4 time periods
    (1...last_4_timestamps.length).each do |i|
      current_ts = last_4_timestamps[i]
      previous_ts = last_4_timestamps[i-1]

      current_chain = option_chains[current_ts]['chain']
      previous_chain = option_chains[previous_ts]['chain']

      current_spot_price = option_chains[current_ts]['spot_price']
      previous_spot_price = option_chains[previous_ts]['spot_price']

      # Find the call option at this strike for both time periods
      current_call = current_chain.call_opts.find { |opt| opt.strike == target_strike }
      previous_call = previous_chain.call_opts.find { |opt| opt.strike == target_strike }

      if current_call && previous_call
        delta = calculate_delta_from_price_history(
          current_call.mark,
          previous_call.mark,
          current_spot_price,
          previous_spot_price,
          'CALL'
        )
        deltas << delta
        puts "  Strike #{target_strike}: #{previous_ts} -> #{current_ts}, delta = #{delta.round(4)}"
      end
    end

    # Average the deltas
    if deltas.any?
      averaged_delta = deltas.sum / deltas.length.to_f
      strike_deltas[target_strike] = averaged_delta
      puts "  Strike #{target_strike}: averaged delta = #{averaged_delta.round(4)}"
    end
  end

  # Add boundary conditions and ATM point for better interpolation
  puts "\nAdding boundary conditions and ATM point:"

  # Min strike: delta = 0.0 (deep ITM call)
  min_strike_val = min_strike(current_option_chain)
  strike_deltas[min_strike_val] = 1.0
  puts "  Min strike #{min_strike_val}: delta = 1.0 (deep ITM)"

  # Max strike: delta = 1.0 (deep OTM call)
  max_strike_val = max_strike(current_option_chain)
  strike_deltas[max_strike_val] = 0.0
  puts "  Max strike #{max_strike_val}: delta = 0.0 (deep OTM)"

  # Step 4: Interpolate deltas for all CALL strikes in the option chain
  puts "\n=== DELTA INTERPOLATION RESULTS ==="
  puts "Key strikes and their averaged deltas:"
  strike_deltas.sort_by { |strike, _| strike }.each do |strike, delta|
    act_call_opt_delta = current_option_chain.call_opts.find do |call_opt|
      call_opt.strike == strike
    end
    puts "  #{strike}: #{delta.round(4)} (actual delta = #{act_call_opt_delta&.delta&.round(4) || 'N/A'})"
  end

  puts "\nInterpolated deltas for all CALL strikes:"

  # Collect data for plotting
  actual_deltas_data = []
  interpolated_deltas_data = []

  current_option_chain.call_opts.sort_by(&:strike).each do |call_opt|
    # interpolated_delta = OptionsTrader::Utils::DeltaInterpolator.interpolate(strike_deltas, call_opt.strike)
    interpolated_delta = OptionsTrader::Utils::PCHIPInterpolator.interpolate(strike_deltas, call_opt.strike)
    puts "  Strike #{call_opt.strike}: interpolated delta = #{interpolated_delta.ceil(2)} (actual delta = #{call_opt.delta&.round(4) || 'N/A'})"

    # Collect data for chart
    interpolated_deltas_data << [call_opt.strike, interpolated_delta.ceil(2)]
    if call_opt.delta
      actual_deltas_data << [call_opt.strike, call_opt.delta]
    end
  end

  # Generate delta comparison chart
  puts "\n=== GENERATING DELTA COMPARISON CHART ==="
  begin
    line_graph = OptionsTrader::Charts::LineGraph.new

    chart_data = [
      { name: "Actual Deltas", data: actual_deltas_data },
      { name: "Interpolated Deltas", data: interpolated_deltas_data }
    ]

    chart_title = "Delta Comparison: CALL Options (#{expiration_date})"
    chart_path = line_graph.generate(
      chart_data,
      title: chart_title,
      x_axis_label: "Strike Price ($)",
      y_axis_label: "Delta",
      min_y: 0.0,
      max_y: 1.0,
      vertical_line: current_spot,
      vertical_line_label: "Spot Price",
      output_filename: "delta_interpolation_#{expiration_date.gsub('-', '')}_#{Time.now.strftime('%H%M%S')}.png"
    )

    puts "Chart saved to: #{chart_path}"
  rescue StandardError => e
    puts "Error generating chart: #{e.message}"
    puts "Continuing without chart..."
  end

else
  puts "Not enough timestamps for delta calculation (need at least 3, have #{timestamps.length})"
end
