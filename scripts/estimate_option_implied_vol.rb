#!/usr/bin/env ruby

require_relative '../config/environment'
require_relative '../lib/options_trader'

VOLATILITY_TOLERANCE = 0.1
RISK_FREE_RATE = 0.04

records = OptionsTrader::OptionChainHistory
  # .where(delta: -0.55...-0.45)
  .where(delta: 0.45...0.5)
  .where.not(underlying_price: nil, bid: nil, ask: nil)
  .order(:expiration_date, :strike, :contract_type)

puts "Found #{records.count} records."

bs_large_delta_diff_cnt = 0
bs_large_price_diff_cnt = 0
crr_large_delta_diff_cnt = 0
crr_large_price_diff_cnt = 0

records.each do |record|
  days_to_expiry = (record.expiration_date.to_date - record.valid_time.to_date).to_i
  time_to_expiry = days_to_expiry / 365.0
  next if time_to_expiry <= 0

  option_type = record.call? ? OptionsTrader::CALL : OptionsTrader::PUT
  market_price = record.mid_price
  next unless market_price && market_price > 0

  # Calculate implied volatility from market price using CRR model
  implied_vol = OptionsTrader::Indicators::ImpliedVolatility.calculate(
    market_price: market_price,
    spot_price: record.underlying_price,
    strike_price: record.strike,
    time_to_expiry: time_to_expiry,
    risk_free_rate: RISK_FREE_RATE,
    option_type: option_type
  )

  next unless implied_vol && implied_vol > 0

  puts "Implied Volatility: #{implied_vol.round(4)} for #{record.underlying_symbol} #{record.contract_type} #{record.expiration_date} $#{record.strike}"

  crr_theoretical_price = OptionsTrader::Indicators::CoxRossRubinstein.calculate(
    spot_price: record.underlying_price,
    strike_price: record.strike,
    time_to_expiry: time_to_expiry,
    risk_free_rate: RISK_FREE_RATE,
    volatility: implied_vol,
    option_type: option_type
  )

  bs_theoretical_price = OptionsTrader::Indicators::BlackScholes.calculate(
    spot_price: record.underlying_price,
    strike_price: record.strike,
    time_to_expiry: time_to_expiry,
    risk_free_rate: RISK_FREE_RATE,
    volatility: implied_vol,
    option_type: option_type
  )

  bs_delta = OptionsTrader::Indicators::Greeks::Delta.calculate(
    spot_price: record.underlying_price,
    strike_price: record.strike,
    time_to_expiry: time_to_expiry,
    risk_free_rate: RISK_FREE_RATE,
    volatility: implied_vol,
    option_type: option_type
  )

  crr_delta = OptionsTrader::Indicators::Greeks::Delta.calculate_crr(
    spot_price: record.underlying_price,
    strike_price: record.strike,
    time_to_expiry: time_to_expiry,
    risk_free_rate: RISK_FREE_RATE,
    volatility: implied_vol,
    option_type: option_type
  )
  crr_delta = -crr_delta
  bs_delta = -bs_delta

  bs_delta_diff = (bs_delta - record.delta).abs
  crr_delta_diff = (crr_delta - record.delta).abs

  bs_price_diff = (bs_theoretical_price - market_price).abs
  crr_price_diff = (crr_theoretical_price - market_price).abs

  puts "#{record.underlying_symbol} #{record.contract_type} #{record.expiration_date} $#{record.strike}"
  puts "  Record Delta: #{record.delta.round(4)} / CRR Delta: #{crr_delta.round(4)} / BS Delta: #{bs_delta.round(4)}"
  puts "  Record Price: $#{market_price.round(2)} / CRR Price: $#{crr_theoretical_price.round(2)} / BS Price: $#{bs_theoretical_price.round(2)}"
  puts "----------------------------------------------------------------"

  bs_large_delta_diff_cnt += 1 if bs_delta_diff > VOLATILITY_TOLERANCE
  crr_large_delta_diff_cnt += 1 if crr_delta_diff > VOLATILITY_TOLERANCE
  crr_large_price_diff_cnt += 1 if crr_price_diff > VOLATILITY_TOLERANCE
  bs_large_price_diff_cnt += 1 if bs_price_diff > VOLATILITY_TOLERANCE
end

puts "####################################################################"
puts "Large BS delta difference: #{bs_large_delta_diff_cnt} - #{bs_large_delta_diff_cnt / records.count.to_f * 100}%"
puts "Large CRR delta difference: #{crr_large_delta_diff_cnt} - #{crr_large_delta_diff_cnt / records.count.to_f * 100}%"
puts "Large BS price difference: #{bs_large_price_diff_cnt} - #{bs_large_price_diff_cnt / records.count.to_f * 100}%"
puts "Large CRR price difference: #{crr_large_price_diff_cnt} - #{crr_large_price_diff_cnt / records.count.to_f * 100}%"
puts "####################################################################"