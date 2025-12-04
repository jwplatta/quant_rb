# frozen_string_literal: true

require 'date'
require 'time'
require_relative './iron_condor_trade'
require_relative 'util'

class SPX1DTEBot
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
        manage_trade(trade)
      elsif inside_trade_window?
        next_exp_date = next_trading_day(Date.today + 1)

        # NOTE: we want to check the expiration date after finding the next next trading day
        # because we do not want to trade over high risk dates by skipping to the next expiration date.
        if low_risk_date?(next_exp_date)
          new_trade = trade_finder.search(expiration_date: next_exp_date)
          send_order(new_trade) if new_trade.status == 'NEW'
        else
          sleep_interval = seconds_until_trade_window_start(Date.today + 1)
          log "Skip trade. Next expiration date #{next_exp_date} is not safe. Sleep #{sleep_interval / 60} minutes."
          sleep(sleep_interval)
        end
      else
        sleep_interval = seconds_until_trade_window_start(Date.today)
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

  def manage_trade(trade)
    config.monitoring_window(Date.today)
    @trade_state_machine.set_monitoring_window(
      config.monitoring_start_time(Date.today),
      config.monitoring_end_time(Date.today),
      config.exit_by_time(Date.today)
    )
    @trade_state_machine.manage(trade)
  end

  def seconds_until_trade_window_start(date)
    now = Time.now
    start_time = config.enter_trade_window_start_time(date)

    if start_time >= now
      0
    else
      start_time += 86_400
      (start_time - now).to_i
    end
  end

  def seconds_until_market_open
    now = Time.now
    today = Date.today
    market_open_time = config.monitoring_start_time(today)
    market_close_time = config.monitoring_end_time(today)

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

  def low_risk_date?(date)
    config.low_risk_date?(date)
  end

  def outside_market_hours?
    now = Time.now
    today = Date.today

    return true unless trading_day?(today)

    market_open_time = config.monitoring_start_time(today)
    market_close_time = config.monitoring_end_time(today)

    return true if now < market_open_time
    return false if now <= market_close_time

    next_trading_date = next_trading_day(today + 1)
    next_open_time = config.monitoring_start_time(next_trading_date)

    now < next_open_time
  end

  def next_trading_day(date)
    next_day = date
    next_day += 1 until trading_day?(next_day)
    next_day
  end

  def trading_day?(date)
    !(date.saturday? || date.sunday? || holiday?(date))
  end

  def inside_trade_window?
    trade_window_start = config.enter_trade_window_start_time(Date.today)
    trade_window_end = config.enter_trade_window_end_time(Date.today)
    curr_time = Time.now
    curr_time >= trade_window_start && curr_time <= trade_window_end
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
