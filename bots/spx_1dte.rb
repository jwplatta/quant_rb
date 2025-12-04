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
require_relative './spx_1dte/bot_config'

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

bot_config = BotConfig.new('bots/config/spx_1dte.yml')

TradesFileManager.setup(TRADES_FILE)
schwab_markets = OptionsTrader::DataProviders::Schwab::Markets.new
schwab_orders = OptionsTrader::DataProviders::Schwab::Orders.new(account_name: ACCOUNT_NAME)
order_manager = PaperOrderManager.new(
  schwab_orders,
  est_fees: bot_config.est_fees_per_contract,
  est_commissions: bot_config.est_commission_per_contract,
  logger: bot_logger
)
trade_finder = IronCondorFinder.new(
  bot_config.underlying_symbol,
  schwab_markets,
  option_root: bot_config.option_root,
  spread_width: bot_config.spread_width,
  max_search_attempts: bot_config.max_search_attempts,
  max_tweak_attempts: bot_config.max_tweak_attempts,
  max_credit: bot_config.max_credit,
  max_put_delta: bot_config.max_put_delta,
  min_put_delta: bot_config.min_put_delta,
  max_call_delta: bot_config.max_call_delta,
  min_call_delta: bot_config.min_call_delta,
  max_total_delta: bot_config.max_total_delta,
  min_credit: bot_config.min_credit,
  min_credit_balance_ratio: bot_config.min_credit_balance_ratio,
  delta_ratio: bot_config.delta_ratio,
  contracts: bot_config.contracts,
  price_increment: bot_config.price_increment,
  exit_prof_thresh: bot_config.exit_prof_thresh,
  exit_loss_thresh: bot_config.exit_loss_thresh,
  logger: bot_logger
)

trade_roller = IronCondorRoller.new(
  underlying_symbol: bot_config.underlying_symbol,
  option_root: bot_config.option_root,
  spread_width: bot_config.spread_width,
  contracts: bot_config.contracts,
  max_delta: bot_config.green_delta,
  est_fees: bot_config.est_fees_per_contract,
  est_commissions: bot_config.est_commission_per_contract,
  price_increment: bot_config.price_increment,
  cost_coverage_perc: 1.0,
  max_search_attempts: bot_config.max_search_attempts,
  markets: schwab_markets,
  logger: bot_logger
)

trade_state_machine = TradeStateMachine.new(
  schwab_markets,
  order_manager,
  trade_roller: trade_roller,
  logger: bot_logger,
  exit_prof_thresh: bot_config.exit_prof_thresh,
  exit_loss_thresh: bot_config.exit_loss_thresh,
  est_fees_per_contract: bot_config.est_fees_per_contract,
  est_commission_per_contract: bot_config.est_commission_per_contract,
  price_increment: bot_config.price_increment,
  yellow_zone_delta: bot_config.yellow_delta,
  red_zone_delta: bot_config.red_delta
)

bot = SPX1DTEBot.new(
  config: bot_config,
  trade_finder: trade_finder,
  trade_state_machine: trade_state_machine,
  order_manager: order_manager,
  logger: bot_logger
)

bot.run