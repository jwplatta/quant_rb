require 'securerandom'
require 'schwab_rb'
require_relative 'data_objects'
require_relative 'constants'
require_relative 'base_order_manager'

class PaperOrderManager < BaseOrderManager
  # NOTE: you're assuming an accepted preview will get filled. But this will not always be the case.
  # After you place the order, you will have to monitor it to see when it gets filled.
  # After it gets filled, then you retrieve the filled order to get these details and then update the trade state.
  def send_order(order_args)
    order_result = schwab_orders.preview_order(order_instruction: order_args[:order_instruction], **order_args)
    order_status = order_result.status
    # REVIEW: now that the order rejects messages are working we can explicitly check that message here
    # has to do with not having the positino in the account for close orders
    if order_status == OrderStatuses::ACCEPTED || (order_status == OrderStatuses::REJECTED && order_args[:order_instruction] == :close)
      @logger.info "Order preview ACCEPTED for #{order_args[:order_instruction]} order."
      # NOTE: schwab will reject these close orders because you don't have an existing trade in the account.
      # So just assume they get accepted.
      order = WorkingOrder.new(
        SecureRandom.uuid().delete('-'),
        order_result.order_id,
        OrderStatuses::WORKING,
        order_result, # REVIEW: convert to a hash or something that isn't an SchwabRb object
        order_args.merge({ schwab_order_id: order_result.order_id }),
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
        order_fill_delay,
        Time.now
      )
      @working_orders << order
      order
    elsif order_status == OrderStatuses::REJECTED && order_args[:order_instruction] == :open
      reject_msgs = order_result.order_validation_result.rejects.map do |rej|
        rej.activity_message.delete_prefix('"').delete_suffix('"')
      end.join('; ')
      @logger.info "Order preview REJECTED for #{order_args[:order_instruction]} order: #{reject_msgs}"
      WorkingOrder.new(
        nil,
        order_result.order_id,
        OrderStatuses::REJECTED,
        order_result,
        order_args,
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

  def order_fill_delay
    Time.now + rand(0.0..30.0)
  end

  private

  def order_result_details(order)
    # NOTE: fallback to the order args for the vertical roll orders
    {
      price: order.order_result.price || order.details[:price],
      fees: order.order_result.fees || 0.0,
      commissions: order.order_result.commission || 0.0,
      quantity: order.order_result.quantity || order.details[:quantity]
    }
  end
end
