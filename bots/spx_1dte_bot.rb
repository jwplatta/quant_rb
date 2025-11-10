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
require_relative './spx_1dte/trade_manager'

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
EXIT_PROF_THRESH = 0.35 # times the original credit received
EXIT_HOUR_THRESH = 12 # PM

EST_FEES_PER_CONTRACT = 2.1
EST_COMMISSION_PER_CONTRACT = 2.6


TradesFileManager.setup(TRADES_FILE)
@schwab_markets = OptionsTrader::DataProviders::Schwab::Markets.new
@schwab_orders = OptionsTrader::DataProviders::Schwab::Orders.new(account_name: ACCOUNT_NAME)
@order_manager = PaperOrderManager.new(
  @schwab_orders,
  est_fees: EST_FEES_PER_CONTRACT,
  est_commissions: EST_COMMISSION_PER_CONTRACT,
  logger: bot_logger
)
@trade_finder = IronCondorFinder.new(
  UNDERLYING_SYMBOL,
  @schwab_markets,
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

@trade_manager = TradeManager.new(
  @schwab_markets,
  @order_manager,
  exit_prof_thresh: EXIT_PROF_THRESH,
  exit_loss_thresh: EXIT_LOSS_THRESH,
  exit_hour_thresh: EXIT_HOUR_THRESH,
  est_fees_per_contract: EST_FEES_PER_CONTRACT,
  est_commission_per_contract: EST_COMMISSION_PER_CONTRACT,
  price_increment: PRICE_INCREMENT,
  logger: bot_logger
)

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

class SPX1DTEBot
  MARKET_OPEN = "08:25 AM" # technically not the market open, but want to start monitoring before then
  MARKET_CLOSE = "03:15 PM"
  TRADE_WINDOW_START = "02:59 PM"
  TRADE_WINDOW_END = "03:15 PM"

  def initialize(
    trade_finder:, trade_manager:, order_manager:, logger:
  )
    @trade_finder = trade_finder
    @trade_manager = trade_manager
    @order_manager = order_manager
    @logger = logger
    @trade = nil
  end

  attr_reader :trade_finder, :trade_manager, :order_manager, :trade, :logger

  def run
    while true
      @trade = if outside_market_hours?
        sleep_interval = seconds_until_market_open
        @logger.info "Outside market hours. Sleeping for #{sleep_interval / 60} minutes."
        sleep(sleep_interval)
      elsif !open_trade.nil?
        open_trade
      elsif inside_trade_window?
        new_trade = trade_finder.search
        send_order(new_trade) if new_trade.status == 'NEW'
      else
        sleep_interval = seconds_until_trade_window_start
        @logger.info "No trade to manage and outside trade window. Sleep #{sleep_interval / 60} minute."
        sleep(sleep_interval)
      end

      next unless @trade

      @trade_manager.watch(@trade)
      @trade_manager.reset
      @logger.info "Trade #{@trade.id} closed. Resetting trade."
    end
  end

  def open_trade
    IronCondorTrade.open_trade
  end

  def seconds_until_trade_window_start
    now = Time.now
    start_time = Time.parse(TRADE_WINDOW_START)
    start_time += 24 * 60 * 60 if start_time <= now
    (start_time - now).to_i
  end

  def seconds_until_market_open
    now = Time.now
    market_open_time = Time.parse("#{Date.today} #{MARKET_OPEN}")
    market_close_time = Time.parse("#{Date.today} #{MARKET_CLOSE}")

    if now <= market_open_time
      (market_open_time - now).to_i
    elsif now >= market_close_time
      market_open_time += 24 * 60 * 60

      if market_open_time.wday == 6
        market_open_time += 2 * 24 * 60 * 60
      elsif market_open_time.wday == 0
        market_open_time += 24 * 60 * 60
      end

      (market_open_time - now).to_i
    end
  end

  def outside_market_hours?
    curr_time = Time.now
    (curr_time.hour <= 8 && curr_time.min < 25) || (curr_time.hour >= 15 && curr_time.min > 15)
  end

  def inside_trade_window?
    curr_time = Time.now
    curr_time >= Time.parse(TRADE_WINDOW_START) && curr_time <= Time.parse(TRADE_WINDOW_END)
  end

  def send_order(trade)
    logger.info "Sending open order for trade #{trade.id}"

    order_status = order_manager.send_order(:open, trade.open_order_args)

    if order_status == 'REJECTED'
      # TODO: if the error can be handled, then try to handle it in the code and send the order again.
      # Otherwise pause and try to find a new trade.
      raise "Open order was rejected!"
    elsif order_status == 'WORKING'
      while order_status == 'WORKING'
        order_status, dtls = order_manager.check_order_status(trade.id)
        if order_status == 'FILLED'

          trade.open(**dtls)
          order_manager.reset

          logger.info "Order filled for trade: #{trade.id}"

          return trade
        end

        logger.info "Order status: #{order_status}. Checking again in 5 seconds."
        sleep(5)
      end
    else
      raise "Unexpected order status: #{order_status}"
    end
  end
end

bot = SPX1DTEBot.new(
  trade_finder: @trade_finder,
  trade_manager: @trade_manager,
  order_manager: @order_manager,
  logger: bot_logger
)

bot.run

#########################################
# STEP 1: Find the trade
# NOTE: finding the trade
# find the straddle price first
# search three times and compare the strategies that have been found to make sure that we're getting a consistent result and handling
# any market fluctuations. Or maybe just check the price a few times before placing the order it is valid.

# So try to find spreads at that are 2-sig away using the straddle price as a reference.
# Is it in the correct credit range?
# If it's too much, then try to move the short legs further out.
# If it's too little, then check delta on the each of the short legs. If one is particularly low, then try moving that delta up until you get enough credit.

# Other things to consider:
# - Is one of the legs providing all the credit? If so, then try to balance it out with affecting the risk profile too much.

# See the IronCondorFinder class.
##########################################

##########################################
# STEP 2: Send the trade
# If the trade does not get filled in a short amount of time, then try reducing the price by 0.05.
# If it still does not get filled, then cancel it and find a new trade.
##########################################
# As you're trying to get the order filled you should check spread_valid?
# You might have to decrease the price a few times until it gets filled. But it must always remain above your min credit.
# If you can't get it filled at your min credit, then cancel the order and find a new trade.
# One way to avoid the risk of trying to get the trade filled is to just find a new trade if you can't get it filled.

# NOTE: right now you're just assuming a successful preview will get filled. But this will not always be the case.
    # Are you place the order. You will have to monitor it to see when it gets filled.
    # After it gets filled, then you retrieve the filled order to get these details and then update the trade state.

# NOTE: opening trade loop


##########################################
# STEP 3: Monitor the trade
# If the trade reaches profit target, then close it.
# If the price of one of the sides reaches 3 times the original credit received, then close it.
# If it's pass 11AM and the it still has not reached its profit target,
# then close the trade for any profit or a small loss.
##########################################