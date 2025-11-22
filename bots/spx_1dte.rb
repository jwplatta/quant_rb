#!/usr/bin/env ruby
# frozen_string_literal: true

require 'pry'
require 'date'
require 'schwab_rb'
require 'json'
require 'fileutils'
require 'logger'

require_relative '../lib/options_trader'
require_relative './spx_1dte/data_objects'
require_relative './spx_1dte/iron_condor_trade'
require_relative './spx_1dte/trades_file_manager'
require_relative './spx_1dte/paper_order_manager'
require_relative './spx_1dte/iron_condor_finder'
require_relative './spx_1dte/iron_condor_roller'
require_relative './spx_1dte/trade_state_machine'
require_relative './spx_1dte/bot'

#####################
### CONFIGURATION ###
#####################

LOG_FILE = ENV.fetch('SPX_1DTE_LOG_FILE', 'logs/spx_1dte_bot.log')
TRADES_FILE = ENV.fetch('SPX_1DTE_TRADES_FILE', 'trades/spx_1dte_trades.json')
ACCOUNT_NAME = ENV.fetch('SPX_1DTE_ACCOUNT_NAME', 'TRADING_BROKERAGE_ACCOUNT')

SchwabRb.configure do |config|
  config.log_file = LOG_FILE
  config.log_level = "INFO"
  config.silence_output = false
end

bot_logger = Logger.new(LOG_FILE)
bot_logger.level = Logger::INFO
bot_logger.formatter = proc do |severity, datetime, progname, msg|
  "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
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
MAX_SEARCH_ATTEMPTS = 5
MAX_TWEAK_ATTEMPTS = 100

# NOTE: risk levels
GREEN_DELTA = 0.15
YELLOW_DELTA = 0.25

MAX_ADJUSTMENTS = 2

# NOTE: exit conditions
EXIT_LOSS_THRESH = 3.0 # times the original credit received
EXIT_PROF_THRESH = 0.5 # times the original credit received
EXIT_HOUR_THRESH = 12 # PM

EST_FEES_PER_CONTRACT = 2.1
EST_COMMISSION_PER_CONTRACT = 2.6

TradesFileManager.setup(TRADES_FILE)
schwab_markets = OptionsTrader::DataProviders::Schwab::Markets.new
schwab_orders = OptionsTrader::DataProviders::Schwab::Orders.new(account_name: ACCOUNT_NAME)
order_manager = PaperOrderManager.new(
  schwab_orders,
  est_fees: EST_FEES_PER_CONTRACT,
  est_commissions: EST_COMMISSION_PER_CONTRACT,
  logger: bot_logger
)
trade_finder = IronCondorFinder.new(
  UNDERLYING_SYMBOL,
  schwab_markets,
  option_root: OPTION_ROOT,
  spread_width: SPREAD_WIDTH,
  max_search_attempts: MAX_SEARCH_ATTEMPTS,
  max_tweak_attempts: MAX_TWEAK_ATTEMPTS,
  max_credit: MAX_CREDIT,
  max_put_delta: MAX_PUT_DELTA,
  min_put_delta: MIN_PUT_DELTA,
  max_call_delta: MAX_CALL_DELTA,
  min_call_delta: MIN_CALL_DELTA,
  max_total_delta: MAX_TOTAL_DELTA,
  min_credit: MIN_CREDIT,
  min_credit_balance_ratio: MIN_CREDIT_BALANCE_RATIO,
  delta_ratio: DELTA_RATIO,
  contracts: CONTRACTS,
  price_increment: PRICE_INCREMENT,
  exit_prof_thresh: EXIT_PROF_THRESH,
  exit_loss_thresh: EXIT_LOSS_THRESH,
  logger: bot_logger
)

trade_roller = IronCondorRoller.new(
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
  markets: schwab_markets,
  logger: bot_logger
)

trade_state_machine = TradeStateMachine.new(
  schwab_markets,
  order_manager,
  exit_prof_thresh: EXIT_PROF_THRESH,
  exit_loss_thresh: EXIT_LOSS_THRESH,
  exit_hour_thresh: EXIT_HOUR_THRESH,
  est_fees_per_contract: EST_FEES_PER_CONTRACT,
  est_commission_per_contract: EST_COMMISSION_PER_CONTRACT,
  price_increment: PRICE_INCREMENT,
  trade_roller: trade_roller,
  logger: bot_logger
)



bot = SPX1DTEBot.new(
  trade_finder: trade_finder,
  trade_state_machine: trade_state_machine,
  order_manager: order_manager,
  logger: bot_logger
)

bot.run