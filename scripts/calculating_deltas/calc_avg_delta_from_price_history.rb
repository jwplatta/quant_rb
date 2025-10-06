#!/usr/bin/env ruby

require 'pry'
require 'date'
require_relative '../config/environment'
require_relative '../lib/options_trader'

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

  return 0.0 if spot_change.abs < 0.0001  # Avoid division by tiny numbers

  delta = price_change / spot_change

  if delta.abs > 1.0 && contract_type == 'CALL' # Delta can't exceed 1.0 for single options
    1.0
  elsif delta.abs > 1.0 && contract_type == 'PUT' # Delta can't be less than -1.0 for single options
    -1.0
  else
    delta
  end
end

####################
### START SCRIPT ###
####################

test_expiry = Date.parse('2025-08-18')
underlying_symbol = '$SPX'
timestamps = [
  DateTime.parse('2025-08-11 14:19:18'),
  DateTime.parse('2025-08-11 14:24:18'),
  DateTime.parse('2025-08-11 14:29:18'),
  DateTime.parse('2025-08-11 14:34:18'),
  DateTime.parse('2025-08-11 14:39:18'),
  DateTime.parse('2025-08-11 14:44:18'),
  DateTime.parse('2025-08-11 14:49:18'),
  DateTime.parse('2025-08-11 14:54:18'),
  DateTime.parse('2025-08-11 14:59:18'),
  DateTime.parse('2025-08-11 15:04:18')
].sort

option_chains = {}

timestamps.each do |ts|
  puts "Building option chain at #{ts}"

  records = OptionsTrader::OptionChainHistory
    .where(expiration_date: '2025-08-18')
    .where(valid_time: ts)
    .where("volume > 5")

  opts_chain = build_options_chain_from_records(records, underlying_symbol)

  option_chains[ts] = {
    'chain' => opts_chain,
    'spot_price' => records.first&.underlying_price
  }
end

start_timestamp_index = 5
timestamp_cnt = 5

# NOTE: calls
timestamps[start_timestamp_index..].each do |ts|
  puts "Building option chain at #{ts} (Index: #{start_timestamp_index})"

  start_index = start_timestamp_index - timestamp_cnt
  prev_timestamps = timestamps[start_index..start_timestamp_index - 1]

  target_opts_chain = option_chains[ts]['chain']

  #########################################################
  est_call_opts = target_opts_chain.call_opts.map do |call|
    # find the average delta
    deltas = prev_timestamps.map do |prev_ts|
      prev_chain = option_chains[prev_ts]['chain']
      prev_call = prev_chain.call_opts.find { |opt| opt.strike == call.strike }
      unless prev_call
        next
      end

      # calculate_delta_from_price_history(current_price, previous_price, current_spot, previous_spot, contract_type = 'CALL')
      calculate_delta_from_price_history(
        call.mark,
        prev_call.mark,
        call.underlying_price,
        prev_call.underlying_price,
        call.put_call.upcase
      )
    end

    avg_delta = deltas.compact.sum / deltas.compact.size.to_f

    puts "CALL Strike: #{call.strike}, Actual Delta: #{call.delta}, Calc Delta: #{avg_delta.round(2)}"
    {
      strike: call.strike.to_i,
      actual_delta: call.delta.to_f,
      calc_delta: avg_delta.round(2).to_f
    }
  end

  ########################################################
  est_put_opts = target_opts_chain.put_opts.map do |put|
    deltas = prev_timestamps.map do |prev_ts|
      prev_chain = option_chains[prev_ts]['chain']
      prev_put = prev_chain.put_opts.find { |opt| opt.strike == put.strike }
      unless prev_put
        next
      end

      # calculate_delta_from_price_history(current_price, previous_price, current_spot, previous_spot, contract_type = 'CALL')
      calculate_delta_from_price_history(
        put.mark,
        prev_put.mark,
        put.underlying_price,
        prev_put.underlying_price,
        put.put_call.upcase
      )
    end

    avg_delta = deltas.compact.sum / deltas.compact.size.to_f

    puts "PUT Strike: #{put.strike}, Actual Delta: #{put.delta}, Calc Delta: #{avg_delta.round(2)}"
    {
      strike: put.strike.to_i,
      actual_delta: put.delta.to_f,
      calc_delta: avg_delta.round(2).to_f
    }
  end

  binding.pry

  start_timestamp_index += 1
  puts "-----------------------------------------------------------\n"
end
