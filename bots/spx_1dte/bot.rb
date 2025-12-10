# frozen_string_literal: true

require 'date'
require 'time'
require_relative 'trade'
require_relative 'util'
require_relative 'constants'

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
  end

  attr_reader :config, :trade_finder, :trade_state_machine, :order_manager, :logger

  def run
    while true
      if inside_market_hours?(Date.today) && open_trade
        manage_trade(open_trade)
      elsif inside_trade_window?(Date.today) && valid_expiration_date?(Date.today + 1) && open_trade.nil?
        trade_finder.search(expiration_date: Date.today + 1).then do |strategy|
          send_order(strategy)
        end
      elsif inside_market_hours?(Date.today) && open_trade.nil?
        sleep_interval = seconds_until_trade_window_start(Date.today)
        log "No open trade. Waiting until trade window. Sleep #{sleep_interval / 60} minutes."
        sleep(sleep_interval)
      else
        sleep_interval = seconds_until_market_open(Date.today + 1)
        log "No open trade. Waiting until market open. Sleep #{sleep_interval / 60} minutes."
        sleep(sleep_interval)
      end
    end
  end

  def open_trade
    Trade.open_trade
  end

  def manage_trade(trade)
    config.monitoring_window(Date.today)
    @trade_state_machine.set_monitoring_window(
      config.monitoring_start_time(Date.today),
      config.monitoring_end_time(Date.today),
      config.exit_by_time(Date.today)
    )
    log "Manage open trade #{open_trade.id}."
    @trade_state_machine.manage(trade)
  end

  def valid_expiration_date?(date)
    trading_day?(date) && low_risk_date?(date)
  end

  def trading_day?(date)
    !(date.saturday? || date.sunday? || holiday?(date))
  end

  def holiday?(date)
    config.holiday?(date)
  end

  def low_risk_date?(date)
    config.low_risk_date?(date)
  end

  def seconds_until_trade_window_start(date)
    now = Time.now
    trade_window_start_time = config.enter_trade_window_start_time(date)
    (trade_window_start_time - now).to_i
  end

  def seconds_until_market_open(date)
    now = Time.now
    market_open_time = config.monitoring_start_time(date)
    (market_open_time - now).to_i
  end

  def inside_market_hours?(date = Date.today)
    now = Time.now
    market_open_time = config.monitoring_start_time(date)
    market_close_time = config.monitoring_end_time(date)

    return false if now < market_open_time
    return true if now <= market_close_time

    false
  end

  def inside_trade_window?(date = Date.today)
    trade_window_start = config.enter_trade_window_start_time(date)
    trade_window_end = config.enter_trade_window_end_time(date)
    curr_time = Time.now
    curr_time >= trade_window_start && curr_time <= trade_window_end
  end

  def send_order(strategy)
    order = order_manager.open_iron_condor(strategy)

    if order.status == OrderStatuses::REJECTED
      # REVIEW: if the error can be handled, then try to handle it in the code and send the order again.
      # Otherwise pause and try to find a new trade.
      raise "Open order was rejected."
    elsif order.status == OrderStatuses::WORKING
      while order.status == OrderStatuses::WORKING
        order = order_manager.check_order_status(order.id)
        if order.status == OrderStatuses::FILLED
          trade = new_trade(
            strategy.price_increment,
            config.exit_loss_mult,
            config.exit_prof_price
          )
          trade.save_event(EventTypes::OPEN_IRON_CONDOR, **order.details)
          log "Order filled for trade #{trade.id}"
        end

        log "Order status: #{order.status}. Checking again in 5 seconds."
        sleep(5)
      end
    else
      raise "Unexpected order status: #{order.status}"
    end
  end

  def new_trade(price_increment, exit_loss_mult, exit_prof_price)
    Trade.new(
      exit_loss_mult: exit_loss_mult,
      exit_prof_price: exit_prof_price,
      price_increment: price_increment,
      trade_history: []
    )
  end

  def log(msg)
    @logger.info msg
  end
end
