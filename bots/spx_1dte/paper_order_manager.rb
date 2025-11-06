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

class PaperOrderManager
  def initialize(schwab_orders, est_fees: nil, est_commissions: nil, logger: nil)
    @schwab_orders = schwab_orders
    @est_fees = est_fees
    @est_commissions = est_commissions
    @logger = logger

    @order_sent = false
    @order_status = 'NO_ORDER'
    @check_fill_count = 0
    @order_result = nil
    @order_details = nil

    @simulated_wait_time = nil
  end

  attr_reader :schwab_orders, :order_sent, :check_fill_count, :order_result, :logger

  # NOTE: you're assuming an accepted preview will get filled. But this will not always be the case.
  # After you place the order, you will have to monitor it to see when it gets filled.
  # After it gets filled, then you retrieve the filled order to get these details and then update the trade state.
  def send_order(order_instruction, order_args)
    reset # NOTE: clear any previous order state
    @order_result = schwab_orders.preview_order(order_instruction: order_instruction, **order_args)

    @logger.info "Order preview #{@order_result.status} for #{order_instruction} order."

    if @order_result.status == 'ACCEPTED' || (@order_result.status == 'REJECTED' && order_instruction == :close)
      # NOTE: schwab will reject these close orders because you don't have an existing trade in the account.
      #So just assume they get accepted.
      @order_sent = true
      @order_status = 'WORKING'
      set_wait_time
    elsif @order_result.status == 'REJECTED' && order_instruction == :open
      @order_status = 'REJECTED'
    else
      raise "Unexpected order preview status: #{@order_result.status}"
    end

    @order_status
  end

  def cancel_order(order_id)
    # NOTE: just assume the cancel succeeds right now
    reset
  end

  def check_order_status(order_id)
    if @order_status == 'WORKING' && Time.now >= @simulated_wait_time
      @order_status = 'FILLED'
      @order_details = order_result_details

      [@order_status, @order_details]
    else
      @check_fill_count += 1

      [@order_status, {}]
    end
  end

  def reset
    @order_sent = false
    @order_status = 'NO_ORDER'
    @check_fill_count = 0
    @order_result = nil
    @order_details = nil
    @simulated_wait_time = nil
  end

  def set_wait_time
    @simulated_wait_time = Time.now + rand(0.0..30.0)
  end

  def order_result_details
    {
      price: @order_result.price,
      fees: @est_fees * @order_result.quantity, # NOTE: I think the schwab order will do this calculation for you.
      commissions: @est_commissions * @order_result.quantity,
      quantity: @order_result.quantity
    }
  end
end
