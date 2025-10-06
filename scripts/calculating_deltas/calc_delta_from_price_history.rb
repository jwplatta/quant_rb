#!/usr/bin/env ruby

require 'pry'
require 'date'
require_relative '../config/environment'
require_relative '../lib/options_trader'
require_relative '../lib/options_trader/charts/compare_deltas'
require_relative 'polynomial_regression'
require_relative 'delta_smoother'

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
    return 1.0
  elsif delta.abs > 1.0 && contract_type == 'PUT' # Delta can't be less than -1.0 for single options
    return -1.0
  end

  delta
end

test_expiry = Date.parse('2025-08-18')
underlying_symbol = '$SPX'
timestamps = [
  '2025-08-11 14:19:18', '2025-08-11 14:24:18', '2025-08-11 14:29:18', '2025-08-11 14:34:18', '2025-08-11 14:39:18',
  '2025-08-11 14:44:18', '2025-08-11 14:49:18', '2025-08-11 14:54:18', '2025-08-11 14:59:18', '2025-08-11 15:04:18'
]

option_chains = {}

timestamps.each do |ts|
  puts "Building option chain at #{ts}"

  records = OptionsTrader::OptionChainHistory
    .where(expiration_date: '2025-08-18')
    .where(valid_time: ts)
    .where("volume > 10")

  opts_chain = build_options_chain_from_records(records, underlying_symbol)

  option_chains[ts] = {
    'chain' => opts_chain,
    'spot_price' => records.first&.underlying_price
  }
end

prev_records = OptionsTrader::OptionChainHistory
  .where(expiration_date: '2025-08-18')
  .where(valid_time: '2025-08-11 14:19:18')

prev_opts_chain = build_options_chain_from_records(prev_records, underlying_symbol)

records = OptionsTrader::OptionChainHistory
  .where(expiration_date: '2025-08-18')
  .where(valid_time: '2025-08-11 14:39:18')
  .where("volume > 10")

spot_price = records.first&.underlying_price
puts "Using spot price of #{spot_price} for calculations."

opts_chain = build_options_chain_from_records(records, underlying_symbol)

call_act_deltas = []
call_calc_deltas = []
put_act_deltas = []
put_calc_deltas = []

opts_chain.call_opts.each do |current_call|
  prev_call = prev_opts_chain.call_opts.find { |opt| opt.strike == current_call.strike }
  next unless prev_call

  new_delta = calculate_delta_from_price_history(
    current_call.mark,
    prev_call.mark,
    current_call.underlying_price,
    prev_call.underlying_price,
    current_call.put_call.upcase
  )

  call_act_deltas << [current_call.strike, current_call.delta]
  call_calc_deltas << [current_call.strike, new_delta.round(4)]

  puts "CALL Strike: #{current_call.strike}, Actual Delta: #{current_call.delta}, Calc Delta: #{new_delta.round(4)}"
end

opts_chain.put_opts.each do |current_put|
  prev_put = prev_opts_chain.put_opts.find { |opt| opt.strike == current_put.strike }
  next unless prev_put

  new_delta = calculate_delta_from_price_history(
    current_put.mark,
    prev_put.mark,
    current_put.underlying_price,
    prev_put.underlying_price,
    current_put.put_call.upcase
  )

  put_act_deltas << [current_put.strike, current_put.delta]
  put_calc_deltas << [current_put.strike, new_delta.round(4)]

  puts "PUT  Strike: #{current_put.strike}, Actual Delta: #{current_put.delta}, Calc Delta: #{new_delta.round(4)}"
end

###############################################################
###################################################
###############################################################
puts "\n\nPredicting Deltas using Polynomial Regression..."

def calc_moneyness(spot_price, strike_price)
  spot_price / strike_price.to_f
end

test_records = OptionsTrader::OptionChainHistory
  .where(expiration_date: '2025-08-18')
  .where(valid_time: '2025-08-11 14:39:18')

test_opts_chain = build_options_chain_from_records(test_records, underlying_symbol)

# empirical_deltas = call_calc_deltas.map do |strike, delta|
#   { moneyness: calc_moneyness(spot_price, strike), delta: delta , weight: 1.0 }
# end

# d_smoother = DeltaSmoother.new(empirical_deltas: empirical_deltas)

# call_calc_deltas.each do |strike, delta|
#   delta = d_smoother.smooth_delta_knn(calc_moneyness(spot_price, strike), k: 40)
#   puts "CALL Strike: #{strike}, Calc Delta: #{delta}, Smoothed Delta: #{delta.round(4)}"
# end

calls_regressor = PolynomialRegression.new(degree: 5)

x_values = call_calc_deltas.map { |strike, _| strike }
y_values = call_calc_deltas.map { |_, delta| delta }

calls_regressor.fit(x_values, y_values)

# call_calc_deltas.each do |strike, delta|
#   predicted_delta = regressor.predict(strike)
#   puts "CALL Strike: #{strike}, Calc Delta: #{delta}, Predicted Delta: #{predicted_delta.round(4)}"
# end

test_opts_chain.call_opts.each do |current_call|
  predicted_delta = calls_regressor.predict(current_call.strike)
  puts "CALL Strike: #{current_call.strike}, Actual Delta: #{current_call.delta}, Predicted Delta: #{predicted_delta.round(2)}"
end

puts "\n\nPredicting PUT Deltas using Polynomial Regression..."

puts_regressor = PolynomialRegression.new(degree: 3)
x_values = put_calc_deltas.map { |strike, _| strike }
y_values = put_calc_deltas.map { |_, delta| delta }
puts_regressor.fit(x_values, y_values)

# put_calc_deltas.each do |strike, delta|
#   predicted_delta = puts_regressor.predict(strike)
#   puts "PUT  Strike: #{strike}, Calc Delta: #{delta}, Predicted Delta: #{predicted_delta.round(4)}"
# end

# puts "---------------------------------------"

test_opts_chain.put_opts.each do |current_put|
  predicted_delta = puts_regressor.predict(current_put.strike)
  puts "PUT  Strike: #{current_put.strike}, Actual Delta: #{current_put.delta}, Predicted Delta: #{predicted_delta.round(4)}"
end

return

### CHARTING ###
delta_chart = OptionsTrader::Charts::CompareDeltas.new

if !call_act_deltas.empty? && !call_calc_deltas.empty?
  call_chart_path = delta_chart.generate(
    call_act_deltas,
    call_calc_deltas,
    'CALL',
    test_expiry
  )
  puts "Call delta comparison chart saved to: #{call_chart_path}"
end

if !put_act_deltas.empty? && !put_calc_deltas.empty?
  put_chart_path = delta_chart.generate(
    put_act_deltas,
    put_calc_deltas,
    'PUT',
    test_expiry
  )
  puts "Put delta comparison chart saved to: #{put_chart_path}"
end