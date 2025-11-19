require 'securerandom'
require 'schwab_rb'
# ORDER_STATUSES = [
#   "ACCEPTED",
#   "PENDING_ACTIVATION",
#   "QUEUED",
#   "WORKING",
#   "REJECTED",
#   "PENDING_CANCEL",
#   "CANCELED",
#   "PENDING_REPLACE",
#   "REPLACED",
#   "FILLED"
# ]
# NOTE: just testing the schwab api wrapper
# schwab_orders = OptionsTrader::DataProviders::Schwab::Orders.new(account_name: ACCOUNT_NAME)
# filled_orders = schwab_orders.account_orders(
#   from_date: Date.today - 1,
#   to_date: DateTime.new(Date.today.year, Date.today.month, Date.today.day, 23, 59, 59, 0),
#   status: 'FILLED'
# )
# transactions = schwab_orders.transactions(
#   from_date: Date.today - 7,
#   to_date: DateTime.new(Date.today.year, Date.today.month, Date.today.day, 23, 59, 59, 0)
# )
WorkingOrder = Struct.new(:id, :schwab_id, :status, :order_result, :details, :check_fill_count, :wait_time)

class PaperOrderManager
  def initialize(schwab_orders, est_fees: nil, est_commissions: nil, logger: nil)
    @schwab_orders = schwab_orders
    @est_fees = est_fees
    @est_commissions = est_commissions
    @logger = logger
    @working_orders = []
  end

  attr_reader :schwab_orders, :check_fill_count, :order_result, :logger

  # NOTE: you're assuming an accepted preview will get filled. But this will not always be the case.
  # After you place the order, you will have to monitor it to see when it gets filled.
  # After it gets filled, then you retrieve the filled order to get these details and then update the trade state.
  def send_order(order_instruction, trade, **kwargs)
    order_args = build_order_args(order_instruction, trade, **kwargs)
    order_result = schwab_orders.preview_order(order_instruction: order_instruction, **order_args)
    order_status = order_result.status

    if order_status == 'ACCEPTED' || (order_status == 'REJECTED' && order_instruction == :close)
      @logger.info "Order preview ACCEPTED for #{order_instruction} order."
      # NOTE: schwab will reject these close orders because you don't have an existing trade in the account.
      #So just assume they get accepted.
      order = WorkingOrder.new(
        SecureRandom.uuid().delete('-'),
        order_result.order_id,
        'WORKING',
        order_result,
        order_args,
        0,
        wait_time
      )
      @working_orders << order
      order
    elsif order_status == 'REJECTED' && order_instruction == :open
      @logger.info "Order preview REJECTED for #{order_instruction} order."
      WorkingOrder.new(nil, order_result.order_id, 'REJECTED', order_result, order_args, 0, nil)
    else
      raise "Unexpected order preview status: #{order_status}"
    end
  end

  def build_order_args(order_instruction, trade, **kwargs)
    if order_instruction == :open
      {
        put_short_symbol: trade.put_spread.short_leg.symbol,
        put_long_symbol: trade.put_spread.long_leg.symbol,
        call_short_symbol: trade.call_spread.short_leg.symbol,
        call_long_symbol: trade.call_spread.long_leg.symbol,
        price: trade.open_price,
        duration: SchwabRb::Orders::Duration::DAY,
        credit_debit: :credit,
        order_instruction: :open,
        quantity: trade.contracts,
        strategy_type: SchwabRb::Order::ComplexOrderStrategyTypes::IRON_CONDOR
      }
    elsif order_instruction == :close
      raise "Must close spreads separately! Unequal contracts." if trade.call_spread.contracts != trade.put_spread.contracts

      {
        put_short_symbol: trade.put_spread.short_leg.symbol,
        put_long_symbol: trade.put_spread.long_leg.symbol,
        call_short_symbol: trade.call_spread.short_leg.symbol,
        call_long_symbol: trade.call_spread.long_leg.symbol,
        price: kwargs[:price],
        duration: SchwabRb::Orders::Duration::DAY,
        credit_debit: :debit,
        order_instruction: :close,
        quantity: trade.contracts,
        strategy_type: SchwabRb::Order::ComplexOrderStrategyTypes::IRON_CONDOR
      }
    else
      raise "Unknown order instruction: #{order_instruction}"
    end
  end

  def cancel_order(order_id)
    # NOTE: just assume the cancel succeeds right now
    logger.info "Canceling order #{order_id}."
    @working_orders = @working_orders.reject { |o| o.id == order_id }
  end

  def check_order_status(order_id)
    idx = @working_orders.index { |o| o.id == order_id }
    return nil if idx.nil?

    order = @working_orders[idx]

    if order.status == 'WORKING' && Time.now >= order.wait_time
      # remove the entry from the array, update and return the same object
      @working_orders.delete_at(idx)
      order.status = 'FILLED'
      order.details = order.details.merge(order_result_details(order))
      order
    else
      @working_orders[idx].check_fill_count = @working_orders[idx].check_fill_count.to_i + 1
      order
    end
  end

  def working?
    @working_orders.any?
  end

  def wait_time
    Time.now + rand(0.0..30.0)
  end

  def order_result_details(order)
    {
      price: order.order_result.price,
      fees: @est_fees * order.order_result.quantity, # NOTE: I think the schwab order will do this calculation for you.
      commissions: @est_commissions * order.order_result.quantity,
      quantity: order.order_result.quantity
    }
  end

  # def open_order_args
  #   @cached_order_args = {
  #     put_short_symbol: put_spread.short_leg.symbol,
  #     put_long_symbol: put_spread.long_leg.symbol,
  #     call_short_symbol: call_spread.short_leg.symbol,
  #     call_long_symbol: call_spread.long_leg.symbol,
  #     price: open_price,
  #     duration: SchwabRb::Orders::Duration::DAY,
  #     credit_debit: :credit,
  #     order_instruction: :open,
  #     quantity: contracts,
  #     strategy_type: SchwabRb::Order::ComplexOrderStrategyTypes::IRON_CONDOR
  #   }
  # end

  # def open_call_spread_args(price, calls_contracts = nil)
  #   @cached_order_args = {
  #     short_leg_symbol: call_spread.short_leg.symbol,
  #     long_leg_symbol: call_spread.long_leg.symbol,
  #     price: price,
  #     duration: SchwabRb::Orders::Duration::DAY,
  #     credit_debit: :credit,
  #     order_instruction: :open,
  #     quantity: calls_contracts || contracts,
  #     strategy_type: SchwabRb::Order::ComplexOrderStrategyTypes::VERTICAL
  #   }
  # end

  # def vertical_roll_args(new_spread, debit_credit)
  #   {
  #     close_short_leg_symbol: old_short_leg_symbol,
  #     close_long_leg_symbol: old_long_leg_symbol,
  #     open_short_leg_symbol: new_short_leg_symbol,
  #     open_long_leg_symbol: new_long_leg_symbol,
  #     price: 0.1,
  #     strategy_type: SchwabRb::Order::ComplexOrderStrategyTypes::VERTICAL_ROLL,
  #     credit_debit: debit_credit,
  #     quantity: contracts
  #   }
  # end

  # def close_call_spread_args(price)
  #   @cached_order_args = {
  #     short_leg_symbol: call_spread.short_leg.symbol,
  #     long_leg_symbol: call_spread.long_leg.symbol,
  #     price: price,
  #     duration: SchwabRb::Orders::Duration::DAY,
  #     credit_debit: :debit,
  #     order_instruction: :close,
  #     quantity: call_spread.contracts,
  #     strategy_type: SchwabRb::Order::ComplexOrderStrategyTypes::VERTICAL
  #   }
  # end

  # def close_put_spread_args(price)
  #   @cached_order_args = {
  #     short_leg_symbol: put_spread.short_leg.symbol,
  #     long_leg_symbol: put_spread.long_leg.symbol,
  #     price: price,
  #     duration: SchwabRb::Orders::Duration::DAY,
  #     credit_debit: :debit,
  #     order_instruction: :close,
  #     quantity: put_spread.contracts,
  #     strategy_type: SchwabRb::Order::ComplexOrderStrategyTypes::VERTICAL
  #   }
  # end

end
