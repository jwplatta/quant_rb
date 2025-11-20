#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../lib/options_trader'
require 'date'
require 'logger'
require 'pry'
require 'optparse'
require 'csv'

def write_option_chain_to_file(opt_chain, expiration_date = nil)
  script_dir = File.dirname(__FILE__)
  safe_symbol = UNDERLYING_SYMBOL.to_s.gsub(/[^A-Za-z0-9_-]/, '').downcase
  file_name = "option_chain_#{safe_symbol}_#{expiration_date}.json"
  path = File.join(script_dir, file_name)

  call_opts_data = opt_chain.call_opts.map do |o|
    {
      symbol: o.symbol,
      strike: o.strike,
      mark: o.mark,
      delta: o.delta,
      gamma: o.gamma,
      expiration_date: o.expiration_date,
      open_interest: o.open_interest,
      volume: o.total_volume
    }
  end

  put_opts_data = opt_chain.put_opts.map do |o|
    {
      symbol: o.symbol,
      strike: o.strike,
      mark: o.mark,
      delta: o.delta,
      gamma: o.gamma,
      expiration_date: o.expiration_date,
      open_interest: o.open_interest,
      volume: o.total_volume
    }
  end

  opt_chain_data = {
    underlying_price: opt_chain.underlying_price,
    call_opts: call_opts_data,
    put_opts: put_opts_data
  }

  File.write(path, JSON.pretty_generate(opt_chain_data))
end

schwab_provider = OptionsTrader::DataProviders::Schwab::Markets.new
markets_service = OptionsTrader::Services::Markets.new(provider: schwab_provider)

expiration_date = Date.parse('2025-10-16')
underlying_symbol = '$SPX'

quotes = markets_service.get_quotes(['$VIX', '$VIX9D', '$VIX3M', '$VVIX', '$SKEW', '$SPX'])

opt_chain = markets_service.get_option_chain(
  underlying_symbol,
  contract_type: 'ALL',
  strike_range: 'ALL',
  to_date: expiration_date,
  from_date: expiration_date
)

binding.pry

# moneyness, dte, open, close, high, low, volume, VIX