#!/usr/bin/env ruby
# frozen_string_literal: true

require 'pry'
require 'date'
require 'schwab_rb'
require 'json'
require 'fileutils'
require 'logger'

require_relative '../../lib/options_trader'
require_relative '../spx_1dte/data_objects'
require_relative '../spx_1dte/iron_condor_roller'
require_relative '../spx_1dte/util'

ACCOUNT_NAME = 'TRADING_BROKERAGE_ACCOUNT'

SchwabRb.configure do |config|
  config.log_file = 'bots/tests/tmp/spx_1dte_bot.log'
  config.log_level = "INFO"
  config.silence_output = false
end


UNDERLYING_SYMBOL = '$SPX'
OPTION_ROOT = 'SPXW'

# TRADING PARAMETERS
SPREAD_WIDTH = 20

# NOTE: should set the credit range based on the VIX and other volatility measures.
MIN_CREDIT = 1.2
MAX_CREDIT = 1.4
DESIRED_DELTA = 0.7
MIN_CREDIT_BALANCE_RATIO = 0.5
DELTA_RATIO = 0.8

# NOTE: Develop the ability to have a bias towards call or put side. Use another ratio.
# The max deltas already start to do this.
MAX_TOTAL_DELTA = 0.14

MAX_CALL_DELTA = 0.07
MIN_CALL_DELTA = 0.03

MAX_PUT_DELTA = 0.1
MIN_PUT_DELTA = 0.04

CONTRACTS = 1
PRICE_INCREMENT = 0.05
MAX_SEARCH_ATTEMPTS = 3
MAX_TWEAK_ATTEMPTS = 100

# NOTE: risk levels
GREEN_DELTA = 0.15
YELLOW_DELTA = 0.25

# NOTE: exit conditions
EXIT_LOSS_THRESH = 3.0 # times the original credit received
EXIT_PROF_THRESH = 0.35 # times the original credit received
EXIT_HOUR_THRESH = 12 # PM

EST_FEES_PER_CONTRACT = 2.1
EST_COMMISSION_PER_CONTRACT = 2.6

schwab_markets = OptionsTrader::DataProviders::Schwab::Markets.new

expiration_date = next_business_day

opt_chain = schwab_markets.get_option_chain(
  UNDERLYING_SYMBOL,
  contract_type: 'ALL',
  strike_range: 'OTM',
  to_date: expiration_date,
  from_date: expiration_date
)

options_chain = OptionsChain.new(
  underlying_price: opt_chain.underlying_price,
  call_opts: opt_chain.call_opts.select { |opt| opt.option_root == OPTION_ROOT },
  put_opts: opt_chain.put_opts.select { |opt| opt.option_root == OPTION_ROOT }
)

call_spread_short_leg = options_chain.call_opts.find { |opt| opt.delta >= 0.22 && opt.delta <= 0.25 }.then do |opt|
  OptionLeg.new(opt.symbol, opt.strike, opt.mark, opt.delta, 'CALL', opt.expiration_date)
end
call_spread_long_leg = options_chain.call_opts.find { |opt| opt.strike == call_spread_short_leg.strike + SPREAD_WIDTH }.then do |opt|
  OptionLeg.new(opt.symbol, opt.strike, opt.mark, opt.delta, 'CALL', opt.expiration_date)
end
call_spread = VerticalSpread.new(call_spread_short_leg, call_spread_long_leg, 'CALL')

put_spread_short_leg = options_chain.put_opts.find { |opt| opt.delta.abs > 0.045 && opt.delta.abs <= 0.055 }.then do |opt|
  OptionLeg.new(opt.symbol, opt.strike, opt.mark, opt.delta, 'PUT', opt.expiration_date)
end
put_spread_long_leg = options_chain.put_opts.find { |opt| opt.strike == put_spread_short_leg.strike - SPREAD_WIDTH }.then do |opt|
  OptionLeg.new(opt.symbol, opt.strike, opt.mark, opt.delta, 'PUT', opt.expiration_date)
end
put_spread = VerticalSpread.new(put_spread_short_leg, put_spread_long_leg, 'PUT')


roller = IronCondorRoller.new(
  underlying_symbol: UNDERLYING_SYMBOL,
  option_root: OPTION_ROOT,
  spread_width: SPREAD_WIDTH,
  contracts: CONTRACTS,
  max_delta: 0.15,
  est_fees: EST_FEES_PER_CONTRACT,
  est_commissions: EST_COMMISSION_PER_CONTRACT,
  price_increment: PRICE_INCREMENT,
  cost_coverage_perc: 1.0,
  max_search_attempts: MAX_SEARCH_ATTEMPTS,
  markets: schwab_markets
)

new_call_spread, new_put_spread = roller.search(
  tested_spread: call_spread,
  untested_spread: put_spread,
  move_size: 5
)

binding.pry