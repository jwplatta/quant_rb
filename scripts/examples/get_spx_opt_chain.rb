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
markets_service = OptionsTrader::Services::Markets.new(provider: schwab_provider)

expiration_dates = [
  Date.parse('2025-11-26'),
  Date.parse('2025-11-28'),
  Date.parse('2025-12-01'),
  Date.parse('2025-12-02'),
  Date.parse('2025-12-03'),
  Date.parse('2025-12-04'),
  Date.parse('2025-12-05')
]
option_root = 'SPXW'

expiration_dates.each do |expiration_date|
  # quotes = markets_service.get_quotes(['$VIX', '$VIX9D', '$VIX3M', '$VVIX', '$SKEW', '$SPX'])
  opt_chain = markets_service.get_option_chain(
    UNDERLYING_SYMBOL,
    contract_type: 'ALL',
    strike_range: 'ALL',
    to_date: expiration_date,
    from_date: expiration_date
  )
  call_opts = opt_chain.call_opts.select { |opt| opt.option_root == option_root }
  put_opts = opt_chain.put_opts.select { |opt| opt.option_root == option_root }

  write_option_chain_to_file('notebooks', opt_chain.underlying_price, call_opts, put_opts, expiration_date)
end