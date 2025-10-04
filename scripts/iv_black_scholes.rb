#!/usr/bin/env ruby

require 'pry'
require 'date'
require_relative '../config/environment'
require_relative '../lib/options_trader'
require_relative '../lib/options_trader/charts/compare_deltas'

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

def calculate_implied_volatility(market_price:, spot_price:, strike:, time_to_expiry:, risk_free_rate:, option_type:)
  objective_function = lambda do |vol|
    theoretical_price = black_scholes_price(spot_price, strike, time_to_expiry, risk_free_rate, vol, option_type)
    theoretical_price - market_price
  end

  vol_low, vol_high = 0.0001, 10.0 # Broad range to capture high volatility scenarios
  f_low = objective_function.call(vol_low)
  f_high = objective_function.call(vol_high)

  return nil if f_low * f_high > 0

  bisection_search(objective_function, vol_low, vol_high, 1e-6)
end

def bisection_search(func, a, b, tolerance, max_iterations = 100)
  fa = func.call(a)
  fb = func.call(b)

  return nil if fa * fb > 0

  (1..max_iterations).each do
    return b if fb.abs < tolerance || (b - a).abs < tolerance

    c = (a + b) / 2.0
    fc = func.call(c)

    if fa * fc < 0
      b = c
      fb = fc
    else
      a = c
      fa = fc
    end
  end

  b
end

def black_scholes_price(spot, strike, time_to_expiry, risk_free_rate, volatility, option_type)
  d1 = (Math.log(spot / strike) + (risk_free_rate + 0.5 * volatility**2) * time_to_expiry) / (volatility * Math.sqrt(time_to_expiry))
  d2 = d1 - volatility * Math.sqrt(time_to_expiry)

  case option_type.upcase
  when 'CALL'
    spot * norm_cdf(d1) - strike * Math.exp(-risk_free_rate * time_to_expiry) * norm_cdf(d2)
  when 'PUT'
    strike * Math.exp(-risk_free_rate * time_to_expiry) * norm_cdf(-d2) - spot * norm_cdf(-d1)
  end
end

def black_scholes_delta(spot_price, strike_price, time_to_expiry, risk_free_rate, volatility, option_type)
  return nil if time_to_expiry <= 0 || volatility <= 0

  # Calculate d1
  d1 = (Math.log(spot_price / strike_price) + \
        (risk_free_rate + 0.5 * volatility**2) * time_to_expiry) / \
       (volatility * Math.sqrt(time_to_expiry))

  # Calculate delta based on option type
  case option_type.upcase
  when 'CALL'
    norm_cdf(d1)
  when 'PUT'
    norm_cdf(d1) - 1.0
  else
    raise ArgumentError, "option_type must be 'CALL' or 'PUT'"
  end
end

def norm_cdf(x)
  return 0.0 if x < -10
  return 1.0 if x > 10

  # Abramowitz and Stegun approximation
  sign = x >= 0 ? 1 : -1
  x = x.abs

  # Constants
  a1 =  0.254829592
  a2 = -0.284496736
  a3 =  1.421413741
  a4 = -1.453152027
  a5 =  1.061405429
  p  =  0.3275911

  t = 1.0 / (1.0 + p * x)
  y = 1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * Math.exp(-x * x)

  0.5 * (1.0 + sign * y)
end

test_expiry = Date.parse('2025-08-18')
underlying_symbol = '$SPX'

records = OptionsTrader::OptionChainHistory
  .where(expiration_date: '2025-08-18')
  .where(valid_time: '2025-08-11 14:39:18')

opts_chain = build_options_chain_from_records(records, underlying_symbol)

# NOTE: steps
# 1. Calculate IV from each option's market price using robust numerical methods
# 2. Use that market-IV to calculate BS delta for that specific option
# 3. This captures the market's actual volatility assumptions at each strike/time

opts_chain.call_opts.each do |call|
  next unless call.mark && call.mark > 0
  days_to_expiry = (Date.parse(call.expiration_date.to_s) - Date.parse('2025-08-11')).to_i
  time_to_expiry = days_to_expiry / 365.0
  next if time_to_expiry <= 0

  implied_vol = calculate_implied_volatility(
    market_price: call.mark,
    spot_price: call.underlying_price,
    strike: call.strike,
    time_to_expiry: time_to_expiry,
    risk_free_rate: 0.045,
    option_type: 'CALL'
  )

  next unless implied_vol && implied_vol > 0

  bs_delta = black_scholes_delta(
    call.underlying_price,
    call.strike,
    time_to_expiry,
    0.045,
    implied_vol,
    'CALL'
  )

  puts "CALL Strike: #{call.strike}, Market Delta: #{call.delta}, Calc Delta: #{bs_delta.round(4)}, Implied Vol: #{implied_vol.round(4)}"
end

opts_chain.put_opts.each do |put|
  next unless put.mark && put.mark > 0
  days_to_expiry = (Date.parse(put.expiration_date.to_s) - Date.parse('2025-08-11')).to_i
  time_to_expiry = days_to_expiry / 365.0
  next if time_to_expiry <= 0

  implied_vol = calculate_implied_volatility(
    market_price: put.mark,
    spot_price: put.underlying_price,
    strike: put.strike,
    time_to_expiry: time_to_expiry,
    risk_free_rate: 0.045,
    option_type: 'PUT'
  )

  next unless implied_vol && implied_vol > 0

  bs_delta = black_scholes_delta(
    put.underlying_price,
    put.strike,
    time_to_expiry,
    0.045,
    implied_vol,
    'PUT'
  )

  puts "PUT  Strike: #{put.strike}, Market Delta: #{put.delta}, Calc Delta: #{bs_delta.round(4)}, Implied Vol: #{implied_vol.round(4)}"
end