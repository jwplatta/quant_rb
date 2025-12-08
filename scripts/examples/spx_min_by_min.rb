#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../lib/options_trader'
require 'date'
require 'logger'
require 'pry'
require 'optparse'
require 'csv'

UNDERLYING_SYMBOL = '$SPX'

def write_option_chain_to_file(dir, underlying_price, call_opts, put_opts, expiration_date = nil)
  sanitized_symbol = UNDERLYING_SYMBOL.to_s.gsub(/[^0-9A-Za-z_\-\.]/, '')
  sanitized_date = expiration_date.to_s.gsub(/[^0-9A-Za-z_\-\.]/, '')
  file_name = "#{sanitized_symbol}_#{sanitized_date}.csv"
  path = File.join(dir, file_name)

  puts "Writing option chain to file: #{path}"

  headers = [
    'contract_type', 'symbol', 'strike', 'expiration_date', 'bid', 'ask', 'mark',
    'delta', 'gamma', 'open_interest', 'total_volume', 'volatility', 'underlying_price'
  ]

  CSV.open(path, 'w') do |csv|
    csv << headers
    [
      ['CALL', call_opts],
      ['PUT', put_opts]
    ].each do |contract_type, options|
      options.each do |o|
        csv << [
          contract_type,
          o.symbol,
          o.strike,
          o.expiration_date,
          o.bid,
          o.ask,
          o.mark,
          o.delta,
          o.gamma,
          o.open_interest,
          o.total_volume,
          o.volatility,
          underlying_price
        ]
      end
    end
  end
end

schwab_provider = OptionsTrader::DataProviders::Schwab::Markets.new
markets_service = OptionsTrader::Services::HistoricalMarkets.new(provider: schwab_provider)
date = "2025-12-05"
spx_data = markets_service.get_price_history_every_min(
  symbol: UNDERLYING_SYMBOL,
  start_datetime: DateTime.parse("#{date} 08:00:00"),
  end_datetime: DateTime.parse("#{date} 17:00:00")
)

vix_data = markets_service.get_price_history_every_min(
  symbol: '$VIX',
  start_datetime: DateTime.parse("#{date} 08:00:00"),
  end_datetime: DateTime.parse("#{date} 17:00:00")
)

rows = {}

trades = [
  ["2025-12-04", "14:54", "Enter", "IronCondor", "5 DEC 25 6905/6925/6765/6745"],
  ["2025-12-05", "9:59", "Exit", "PutSpread", "5 DEC 25 6765/6745"],
  ["2025-12-05", "10:00", "RollAway", "CallSpread", "5 DEC 25 6905/6925 to 6910/6930"],
  ["2025-12-05", "10:01", "Enter", "PutSpread", "5 DEC 25 6835/6815"],
  ["2025-12-05", "11:02", "Exit", "CallSpread", "5 DEC 25 6910/6930"],
  ["2025-12-05", "12:30", "Exit", "PutSpread", "5 DEC 25 6835/6815"]
]

spx_data.candles.each do |candle|
  timestamp = Time.at(candle.datetime_ms / 1000.0).getlocal("-06:00")
  rows[timestamp] ||= {}
  rows[timestamp][:spx_high] = candle.high
  rows[timestamp][:spx_low] = candle.low
  rows[timestamp][:spx_open] = candle.open
  rows[timestamp][:spx_close] = candle.close
end

vix_data.candles.each do |candle|
  timestamp = Time.at(candle.datetime_ms / 1000.0)
  rows[timestamp] ||= {}
  rows[timestamp][:vix_high] = candle.high
  rows[timestamp][:vix_low] = candle.low
  rows[timestamp][:vix_open] = candle.open
  rows[timestamp][:vix_close] = candle.close
end

trades.each do |trade_date, trade_time, action, strategy, description|
  timestamp = Time.parse("#{trade_date} #{trade_time} -06:00").to_time
  rows[timestamp] ||= {}
  rows[timestamp][:action] = action
  rows[timestamp][:strategy] = strategy
  rows[timestamp][:description] = description
end

CSV.open("spx_min_by_min_#{date}.csv", 'w') do |csv|
  csv << [
    'timestamp',
    'spx_open',
    'spx_high',
    'spx_low',
    'spx_close',
    'vix_open',
    'vix_high',
    'vix_low',
    'vix_close',
    'action',
    'strategy',
    'description'
  ]

  rows.keys.sort.each do |timestamp|
    row = rows[timestamp]
    csv << [
      timestamp,
      row[:spx_open],
      row[:spx_high],
      row[:spx_low],
      row[:spx_close],
      row[:vix_open],
      row[:vix_high],
      row[:vix_low],
      row[:vix_close],
      row[:action],
      row[:strategy],
      row[:description]
    ]
  end
end