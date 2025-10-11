#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../lib/options_trader'
require 'date'
require 'logger'
require 'pry'
require 'optparse'
require 'csv'

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