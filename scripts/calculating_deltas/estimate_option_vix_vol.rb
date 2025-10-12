#!/usr/bin/env ruby

require_relative '../config/environment'
require_relative '../lib/options_trader'
require 'date'

VOLATILITY_TOLERANCE = 0.1
RISK_FREE_RATE = 0.05

dividend_yield = 0.015
spx_index = '$SPX'
vix_index = '$VIX'
vix9d_index = '$VIX9D'

timestamp = '2025-08-11 14:04:18'

provider = OptionsTrader::DataProviders::Schwab::Markets.new
end_datetime = DateTime.parse('2025-08-11 14:06:00').new_offset('-05:00')
start_datetime = DateTime.parse('2025-08-11 14:04:00').new_offset('-05:00')

records = OptionsTrader::OptionChainHistory
  .where(valid_time: '2025-08-11 14:04:18')
  .where(delta: 0.03...0.97)

examples = records.map do |record|
  {
    underlying_symbol: record.underlying_symbol,
    symbol: record.symbol,
    contract_type: record.contract_type.downcase,
    expiration_date: DateTime.parse(record.expiration_date.to_s),
    strike: record.strike.to_i,
    delta: record.delta.to_f,
    price: record.mid_price.to_f,
    valid_time: DateTime.parse(record.valid_time.to_s).new_offset('-05:00')
  }
end

spx_price_hist = provider.get_price_history_every_min(
  symbol: spx_index,
  start_datetime: start_datetime,
  end_datetime: end_datetime
)

vix_price_hist = provider.get_price_history_every_min(
  symbol: vix_index,
  start_datetime: start_datetime,
  end_datetime: end_datetime
)

vix9d_price_hist = provider.get_price_history_every_min(
  symbol: vix9d_index,
  start_datetime: start_datetime,
  end_datetime: end_datetime
)

puts "Found #{records.count} records."

bs_large_delta_diff_cnt = 0
bs_large_price_diff_cnt = 0
crr_large_delta_diff_cnt = 0
crr_large_price_diff_cnt = 0

examples.each do |example|
  dt = example[:valid_time]
  dte = (example[:expiration_date].to_date - dt.to_date).to_i
  market_price = example[:price]
  option_type = example[:contract_type].downcase == 'call' ? OptionsTrader::CALL : OptionsTrader::PUT

  spx_price = spx_price_hist.candles.find do |c|
    c.datetime == DateTime.new(dt.year, dt.month, dt.day, dt.hour, dt.min, 0, dt.offset)
  end
  vix_price = vix_price_hist.candles.find do |c|
    c.datetime == DateTime.new(dt.year, dt.month, dt.day, dt.hour, dt.min, 0, dt.offset)
  end
  vix9d_price = vix9d_price_hist.candles.find do |c|
    c.datetime == DateTime.new(dt.year, dt.month, dt.day, dt.hour, dt.min, 0, dt.offset)
  end

  recent_vix_hist = vix_price_hist.candles.select do |c|
    c.datetime < DateTime.new(dt.year, dt.month, dt.day, dt.hour, dt.min, 0, dt.offset)
  end.map(&:close)
  # recent_vix_hist = []

  vix_vol = OptionsTrader::Indicators::VIXVolatility.calculate(
    spot_price: spx_price.close,
    strike_price: example[:strike],
    dte: dte,
    vix: vix_price.close,
    vix9d: vix9d_price.close,
    current_timestamp: dt,
    option_type: option_type,
    recent_vix_history: recent_vix_hist
  )
  puts "VIX VOL: #{vix_vol}"
  time_to_expiry = dte / 365.0
  spot_price = spx_price.close
  strike_price = example[:strike]

  crr_theoretical_price = OptionsTrader::Indicators::CoxRossRubinstein.calculate(
    spot_price: spot_price,
    strike_price: strike_price,
    time_to_expiry: time_to_expiry,
    risk_free_rate: RISK_FREE_RATE,
    volatility: vix_vol,
    option_type: option_type,
    dividend_yield: dividend_yield
  )

  bs_theoretical_price = OptionsTrader::Indicators::BlackScholes.calculate(
    spot_price: spot_price,
    strike_price: strike_price,
    time_to_expiry: time_to_expiry,
    risk_free_rate: RISK_FREE_RATE,
    volatility: vix_vol,
    option_type: option_type,
    dividend_yield: dividend_yield
  )

  bs_delta = OptionsTrader::Indicators::Greeks::Delta.calculate(
    spot_price: spot_price,
    strike_price: strike_price,
    time_to_expiry: time_to_expiry,
    risk_free_rate: RISK_FREE_RATE,
    volatility: vix_vol,
    option_type: option_type
  )

  crr_delta = OptionsTrader::Indicators::Greeks::Delta.calculate_crr(
    spot_price: spot_price,
    strike_price: strike_price,
    time_to_expiry: time_to_expiry,
    risk_free_rate: RISK_FREE_RATE,
    volatility: vix_vol,
    option_type: option_type,
    dividend_yield: dividend_yield
  )

  crr_delta = crr_delta
  bs_delta = bs_delta

  bs_delta_diff = (bs_delta - example[:delta]).abs
  crr_delta_diff = (crr_delta - example[:delta]).abs

  bs_price_diff = (bs_theoretical_price - market_price).abs
  crr_price_diff = (crr_theoretical_price - market_price).abs

  bs_large_delta_diff_cnt += 1 if bs_delta_diff > VOLATILITY_TOLERANCE
  crr_large_delta_diff_cnt += 1 if crr_delta_diff > VOLATILITY_TOLERANCE
  crr_large_price_diff_cnt += 1 if crr_price_diff > VOLATILITY_TOLERANCE
  bs_large_price_diff_cnt += 1 if bs_price_diff > VOLATILITY_TOLERANCE

  puts "#{example[:underlying_symbol]} #{example[:contract_type]} #{example[:expiration_date]} $#{example[:strike]}"
  puts "  Record Delta: #{example[:delta].round(4)} / CRR Delta: #{crr_delta.round(4)} / BS Delta: #{bs_delta.round(4)}"
  puts "  Record Price: $#{market_price.round(2)} / CRR Price: $#{crr_theoretical_price.round(2)} / BS Price: $#{bs_theoretical_price.round(2)}"
  puts "----------------------------------------------------------------"
end

puts "####################################################################"
puts "Large BS delta difference: #{bs_large_delta_diff_cnt} - #{bs_large_delta_diff_cnt / examples.count.to_f * 100}%"
puts "Large CRR delta difference: #{crr_large_delta_diff_cnt} - #{crr_large_delta_diff_cnt / examples.count.to_f * 100}%"
puts "Large BS price difference: #{bs_large_price_diff_cnt} - #{bs_large_price_diff_cnt / examples.count.to_f * 100}%"
puts "Large CRR price difference: #{crr_large_price_diff_cnt} - #{crr_large_price_diff_cnt / examples.count.to_f * 100}%"
puts "####################################################################"