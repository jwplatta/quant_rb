require 'securerandom'
require 'schwab_rb'
require_relative 'data_objects'
require_relative 'constants'

class PaperOrderManager
  def initialize(schwab_orders, fill_wait_time: 20, est_fees: nil, est_commissions: nil, logger: nil)
    @schwab_orders = schwab_orders
    @est_fees = est_fees
    @est_commissions = est_commissions
    @logger = logger
    @working_orders = []
    @fill_wait_time = fill_wait_time
  end

  attr_reader :schwab_orders, :fill_wait_time, :check_fill_count, :logger

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

  # NOTE: you're assuming an accepted preview will get filled. But this will not always be the case.
  # After you place the order, you will have to monitor it to see when it gets filled.
  # After it gets filled, then you retrieve the filled order to get these details and then update the trade state.
  def send_order(order_args)
    order_result = schwab_orders.preview_order(order_instruction: order_args[:order_instruction], **order_args)
    order_status = order_result.status

    if order_status == OrderStatuses::ACCEPTED || (order_status == OrderStatuses::REJECTED && order_args[:order_instruction] == :close)
      @logger.info "Order preview ACCEPTED for #{order_args[:order_instruction]} order."
      # NOTE: schwab will reject these close orders because you don't have an existing trade in the account.
      #So just assume they get accepted.
      order = WorkingOrder.new(
        SecureRandom.uuid().delete('-'),
        order_result.order_id,
        OrderStatuses::WORKING,
        order_result, # REVIEW: convert to a hash or something that isn't an SchwabRb object
        order_args.merge({ schwab_order_id: order_result.order_id }),
        0,
        order_fill_delay,
        Time.now
      )
      @working_orders << order
      order
    elsif order_args[:strategy_type] == SchwabRb::Order::ComplexOrderStrategyTypes::VERTICAL_ROLL
      # NOTE: the vertical roll orders will be rejected because the initial spread doesn't exist in the account.
      @logger.info "Order preview ACCEPTED for #{order_args[:order_instruction]} VERTICAL_ROLL order."
      order = WorkingOrder.new(
        SecureRandom.uuid().delete('-'),
        order_result.order_id,
        OrderStatuses::WORKING,
        order_result,
        order_args.merge({ schwab_order_id: order_result.order_id }),
        0,
        order_fill_delay,
        Time.now
      )
      @working_orders << order
      order
    elsif order_status == OrderStatuses::REJECTED && order_args[:order_instruction] == :open
      @logger.info "Order preview REJECTED for #{order_args[:order_instruction]} order."
      WorkingOrder.new(
        nil,
        order_result.order_id,
        OrderStatuses::REJECTED,
        order_result,
        order_args,
        0,
        nil
      )
    else
      raise "Unexpected order preview status: #{order_status}"
    end
  end

  def cancel_order(order_id)
    # NOTE: just assume the cancel succeeds right now
    order = @working_orders.find { |o| o.id == order_id }
    @working_orders = @working_orders.reject { |o| o.id == order_id }
    order.status = OrderStatuses::CANCELED
    order
  end

  def check_all_order_statuses
    @working_orders.each do |order|
      check_order_status(order.id)
    end
  end

  def check_order_status(order_id)
    idx = @working_orders.index { |o| o.id == order_id }
    return nil if idx.nil?

    order = @working_orders[idx]

    if order.status == OrderStatuses::WORKING && Time.now >= order.fill_time
      # remove the entry from the array, update and return the same object
      @working_orders.delete_at(idx)
      order.status = OrderStatuses::FILLED
      order.details = order.details.merge(order_result_details(order))
      order
    elsif order.status == OrderStatuses::WORKING && Time.now > order.sent_time + @fill_wait_time
      # NOTE: cancel if it has been working too long
      cancel_order(order.id)
    else
      order
    end
  end

  def working_orders_size
    @working_orders.size
  end

  def working?
    @working_orders.any?
  end

  def order_fill_delay
    Time.now + rand(0.0..30.0)
  end

  def order_result_details(order)
    # NOTE: fallback to the order args for the vertical roll orders
    {
      price: order.order_result.price || order.details[:price],
      fees: @est_fees * (order.order_result.quantity || order.details[:quantity]), # NOTE: I think the schwab order will do this calculation for you.
      commissions: @est_commissions * (order.order_result.quantity || order.details[:quantity]),
      quantity: order.order_result.quantity || order.details[:quantity]
    }
  end

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
