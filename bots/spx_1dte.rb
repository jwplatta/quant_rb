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
require_relative './spx_1dte/trades_file_manager'
require_relative './spx_1dte/paper_order_manager'
require_relative './spx_1dte/order_manager'
require_relative './spx_1dte/iron_condor_finder'
require_relative './spx_1dte/iron_condor_roller'
require_relative './spx_1dte/trade_state_machine'
require_relative './spx_1dte/bot'
require_relative './spx_1dte/bot_config'
require_relative './spx_1dte/strategy_pricer'

#####################
### CONFIGURATION ###
#####################

LOG_FILE = ENV.fetch('SPX_1DTE_LOG_FILE', 'logs/spx_1dte_bot.log')
TRADES_FILE = ENV.fetch('SPX_1DTE_TRADES_FILE', 'trades/spx_1dte_trades.json')

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
  credit_balance_ratio: bot_config.credit_balance_ratio,
  delta_ratio: bot_config.delta_ratio,
  quantity: bot_config.quantity,
  price_increment: bot_config.price_increment,
  logger: bot_logger
)

order_manager = if bot_config.trade_mode == 'paper'
  bot_logger.info "Trade mode: PAPER"
  PaperOrderManager.new(
    OptionsTrader::DataProviders::Schwab::Orders.new(account_name: bot_config.account_name),
    fill_wait_time: 20,
    logger: bot_logger
  )
elsif bot_config.trade_mode == 'live'
  bot_logger.info "Trade mode: LIVE"
  OrderManager.new(
    OptionsTrader::DataProviders::Schwab::Orders.new(account_name: bot_config.account_name),
    fill_wait_time: 20,
    logger: bot_logger
  )
else
  raise "Invalid trade mode: #{bot_config.trade_mode}"
end

trade_state_machine = TradeStateMachine.new(
  StrategyPricer.new(schwab_markets, bot_logger),
  order_manager,
  yellow_zone_delta: bot_config.yellow_delta,
  red_zone_delta: bot_config.red_delta,
  logger: bot_logger
)

bot = SPX1DTEBot.new(
  config: bot_config,
  trade_finder: trade_finder,
  trade_state_machine: trade_state_machine,
  order_manager: order_manager,
  logger: bot_logger
)

bot.run