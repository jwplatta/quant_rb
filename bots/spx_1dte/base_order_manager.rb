require 'securerandom'
require 'schwab_rb'
require_relative 'data_objects'
require_relative 'constants'

class BaseOrderManager
  def initialize(schwab_orders, fill_wait_time: 20, logger: nil)
    @schwab_orders = schwab_orders
    @logger = logger
    @working_orders = []
    @fill_wait_time = fill_wait_time
  end

  attr_reader :schwab_orders, :fill_wait_time, :logger

  def open_iron_condor(strategy, **kwargs)
    order_args = open_iron_condor_args(strategy)
    send_order(order_args)
  rescue => e
    logger.error "Error sending open iron condor order: #{e.message}"
    raise e
  end

  def close_iron_condor(strategy, **kwargs)
    order_args = close_iron_condor_args(strategy)
    send_order(order_args)
  rescue => e
    logger.error "Error sending close iron condor order: #{e.message}"
    raise e
  end

  def rollaway_spread(old_spread, new_spread, **kwargs)
    price = kwargs.fetch(:price) { raise ArgumentError, "Missing required :price in kwargs" }
    order_args = vertical_roll_args(old_spread, new_spread, price, :debit)
    send_order(order_args)
  rescue => e
    logger.error "Error sending roll away spread order: #{e.message}"
    raise e
  end

  def rollup_spread(old_spread, new_spread, **kwargs)
    price = kwargs.fetch(:price) { raise ArgumentError, "Missing required :price in kwargs" }
    order_args = vertical_roll_args(old_spread, new_spread, price, :credit)
    send_order(order_args)
  rescue => e
    logger.error "Error sending roll up spread order: #{e.message}"
    raise e
  end

  def close_spread(strategy, **kwargs)
    order_args = close_spread_args(strategy)
    send_order(order_args)
  rescue => e
    logger.error "Error sending close spread order: #{e.message}"
    raise e
  end

  def open_spread(strategy, **kwargs)
    order_args = open_spread_args(strategy)
    send_order(order_args)
  rescue => e
    logger.error "Error sending open spread order: #{e.message}"
    raise e
  end

  def check_all_order_statuses
    @working_orders.each do |order|
      check_order_status(order.id)
    end
  end

  def working_orders_size
    @working_orders.size
  end

  def working?
    @working_orders.any?
  end

  # Subclasses must implement these methods
  def send_order(order_args)
    raise NotImplementedError, "Subclass must implement send_order"
  end

  def check_order_status(order_id)
    raise NotImplementedError, "Subclass must implement check_order_status"
  end

  def cancel_order(order_id)
    raise NotImplementedError, "Subclass must implement cancel_order"
  end

  private

  def open_iron_condor_args(strategy)
    raise "Spreads must have equal number of contracts." if strategy.call_spread.quantity != strategy.put_spread.quantity

    base_iron_condor_args(strategy).merge({
      credit_debit: :credit,
      order_instruction: :open
    })
  end

  def close_iron_condor_args(strategy)
    raise "Spreads must have equal number of contracts." if strategy.call_spread.quantity != strategy.put_spread.quantity

    base_iron_condor_args(strategy).merge({
      credit_debit: :debit,
      order_instruction: :close
    })
  end

  def base_iron_condor_args(strategy)
     {
      put_short_symbol: strategy.put_spread.short_leg.symbol,
      put_long_symbol: strategy.put_spread.long_leg.symbol,
      call_short_symbol: strategy.call_spread.short_leg.symbol,
      call_long_symbol: strategy.call_spread.long_leg.symbol,
      price: strategy.price_rounded_down_by_increment,
      duration: SchwabRb::Orders::Duration::DAY,
      quantity: strategy.quantity,
      strategy_type: SchwabRb::Order::ComplexOrderStrategyTypes::IRON_CONDOR
    }
  end

  def vertical_roll_args(old_spread, new_spread, price, debit_credit)
    {
      close_short_leg_symbol: old_spread.short_leg.symbol,
      close_long_leg_symbol: old_spread.long_leg.symbol,
      open_short_leg_symbol: new_spread.short_leg.symbol,
      open_long_leg_symbol: new_spread.long_leg.symbol,
      price: price,
      credit_debit: debit_credit,
      order_instruction: :open,
      quantity: new_spread.quantity,
      strategy_type: SchwabRb::Order::ComplexOrderStrategyTypes::VERTICAL_ROLL
    }
  end

  def open_spread_args(strategy)
    base_spread_args(strategy).merge({
      credit_debit: :credit,
      order_instruction: :open
    })
  end

  def close_spread_args(strategy)
    base_spread_args(strategy).merge({
      credit_debit: :debit,
      order_instruction: :close
    })
  end

  def base_spread_args(strategy)
    {
      short_leg_symbol: strategy.short_leg.symbol,
      long_leg_symbol: strategy.long_leg.symbol,
      price: strategy.price,
      duration: SchwabRb::Orders::Duration::DAY,
      quantity: strategy.quantity,
      strategy_type: SchwabRb::Order::ComplexOrderStrategyTypes::VERTICAL
    }
  end
end
