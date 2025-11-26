# frozen_string_literal: true

require 'date'
require_relative './iron_condor_trade'
require_relative 'util'

class SPX1DTEBot
  # NOTE: technically not the market open and close, but want to start monitoring before
  # the market open and during the extended hours
  MARKET_OPEN = "08:25 AM"
  MARKET_CLOSE = "03:15 PM"
  TRADE_WINDOW_START = "02:59 PM"
  TRADE_WINDOW_END = "03:15 PM"

  def initialize(
    config:,
    trade_finder:,
    trade_state_machine:,
    order_manager:,
    logger:
  )
    @config = config
    @trade_finder = trade_finder
    @trade_state_machine = trade_state_machine
    @order_manager = order_manager
    @logger = logger
    @trade = nil
  end

  attr_reader :config, :trade_finder, :trade_state_machine, :order_manager, :trade, :logger

  def run
    while true
      if outside_market_hours?
        sleep_interval = seconds_until_market_open
        log "Outside market hours. Sleep #{sleep_interval / 60} minutes."
        sleep(sleep_interval)
      elsif open_trade
        trade = open_trade
        log "Watching open trade #{trade.id}."
        watch_trade(trade)
      elsif inside_trade_window?
        next_exp_date = next_vaild_expiration_date

        if safe_expiration_date?(next_exp_date)
          new_trade = trade_finder.search(expiration_date: next_exp_date)
          send_order(new_trade) if new_trade.status == 'NEW'
        else
          log "Next expiration date #{next_exp_date} is not safe. Skipping trade."
        end
      else
        sleep_interval = seconds_until_trade_window_start
        log "No trade to manage and outside trade window. Sleep #{sleep_interval / 60} minutes."
        sleep(sleep_interval)
      end
    end
  end

  def log(msg)
    @logger.info msg
  end

  def open_trade
    IronCondorTrade.open_trade
  end

  def next_vaild_expiration_date
    # TODO: get rid of the while loop
    exp_date = Date.today + 1
    while true
      if exp_date.saturday?
        exp_date += 2
      elsif exp_date.sunday?
        exp_date += 1
      elsif holiday?(exp_date)
        exp_date += 1
      else
        break
      end
    end

    exp_date
  end

  def watch_trade(trade)
    @trade_state_machine.watch(trade)
    @logger.info "Trade #{trade.id} closed. Resetting trade."
    @trade_state_machine.reset
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

  def holiday?(date)
    config.holiday?(date)
  end

  def safe_expiration_date?(date)
    config.safe_expiration_date?(date)
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

    order = order_manager.open_iron_condor(trade)

    if order.status == 'REJECTED'
      # TODO: if the error can be handled, then try to handle it in the code and send the order again.
      # Otherwise pause and try to find a new trade.
      raise "Open order was rejected!"
    elsif order.status == 'WORKING'
      while order.status == 'WORKING'
        order = order_manager.check_order_status(order.id)
        if order.status == 'FILLED'
          trade.open(**order.details)
          logger.info "Order filled for trade #{trade.id}"
        end

        logger.info "Order status: #{order.status}. Checking again in 5 seconds."
        sleep(5)
      end
    else
      raise "Unexpected order status: #{order.status}"
    end
  end
end
