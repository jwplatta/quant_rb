require 'securerandom'
require 'schwab_rb'
require_relative 'data_objects'
require_relative 'constants'
require_relative 'base_order_manager'

class OrderManager < BaseOrderManager
  # Preview the order first, then place it if preview succeeds
  # Monitor the order after placement to track status changes
  def send_order(order_args)
    preview_result = schwab_orders.preview_order(order_instruction: order_args[:order_instruction], **order_args)
    preview_status = preview_result.status

    if preview_status == OrderStatuses::REJECTED
      @logger.error "Order preview REJECTED for #{order_args[:order_instruction]} order."
      return WorkingOrder.new(
        nil,
        preview_result.order_id,
        OrderStatuses::REJECTED,
        preview_result,
        order_args,
        nil,
        Time.now
      )
    end

    @logger.info "Order preview ACCEPTED for #{order_args[:order_instruction]} order. Placing order..."

    placed_order = schwab_orders.place_order(order_instruction: order_args[:order_instruction], **order_args)

    if placed_order.nil? || placed_order.status == OrderStatuses::REJECTED
      @logger.error "Failed to place order"
      return WorkingOrder.new(
        nil,
        nil,
        OrderStatuses::REJECTED,
        preview_result,
        order_args,
        nil,
        Time.now
      )
    end

    @logger.info "Order placed successfully: #{placed_order.order_id}"

    order = WorkingOrder.new(
      SecureRandom.uuid().delete('-'),
      placed_order.order_id,
      OrderStatuses::WORKING,
      placed_order,
      order_args.merge({ schwab_order_id: placed_order.order_id }),
      nil, # No preset fill time - we'll check status via API
      Time.now
    )
    @working_orders << order
    order
  rescue => e
    @logger.error "Error in send_order: #{e.message}"
    @logger.error e.backtrace.join("\n")
    raise e
  end

  def cancel_order(order_id)
    order = @working_orders.find { |o| o.id == order_id }
    return nil if order.nil?

    # Call Schwab API to cancel the order
    success = schwab_orders.cancel_order(order.schwab_id)

    if success
      @logger.info "Order canceled successfully: #{order_id}"
      @working_orders = @working_orders.reject { |o| o.id == order_id }
      order.status = OrderStatuses::CANCELED
      order
    else
      @logger.error "Failed to cancel order: #{order_id}"
      nil
    end
  rescue => e
    @logger.error "Error canceling order #{order_id}: #{e.message}"
    raise e
  end

  def check_order_status(order_id)
    idx = @working_orders.index { |o| o.id == order_id }
    return nil if idx.nil?

    order = @working_orders[idx]

    # Only check status for WORKING orders
    return order unless order.status == OrderStatuses::WORKING

    # Fetch the current order status from Schwab
    schwab_order = schwab_orders.get_order(order.schwab_id)

    case schwab_order.status
    when 'FILLED'
      # Remove from working orders and mark as filled
      @working_orders.delete_at(idx)
      order.status = OrderStatuses::FILLED
      order.details = order.details.merge(order_result_details(schwab_order))
      @logger.info "Order FILLED: #{order_id}"
      order
    when 'CANCELED'
      @working_orders.delete_at(idx)
      order.status = OrderStatuses::CANCELED
      @logger.info "Order CANCELED: #{order_id}"
      order
    when 'REJECTED'
      # Remove from working orders and mark as rejected
      @working_orders.delete_at(idx)
      order.status = OrderStatuses::REJECTED
      @logger.info "Order REJECTED: #{order_id}"
      order
    when 'WORKING', 'PENDING_ACTIVATION', 'QUEUED', 'ACCEPTED'
      # Check if it's been working too long
      if Time.now > order.sent_time + @fill_wait_time
        @logger.warn "Order has been working for too long. Canceling: #{order_id}"
        cancel_order(order.id)
      else
        order
      end
    else
      @logger.warn "Unknown order status: #{schwab_order.status}"
      order
    end
  rescue => e
    @logger.error "Error checking order status for #{order_id}: #{e.message}"
    order
  end

  private

  def order_result_details(schwab_order)
    # Extract details from the Schwab order object
    # NOTE: The structure may vary based on the Schwab API response
    {
      price: schwab_order.price,
      fees: extract_fees(schwab_order),
      commissions: extract_commissions(schwab_order),
      quantity: schwab_order.quantity
    }
  end

  def extract_fees(schwab_order)
    # Extract fees from the order if available
    schwab_order.order_activity_collection&.first&.execution_legs&.sum { |leg| leg.fees || 0.0 } || 0.0
  rescue
    0.0
  end

  def extract_commissions(schwab_order)
    # Extract commissions from the order if available
    schwab_order.order_activity_collection&.first&.execution_legs&.sum { |leg| leg.commissions || 0.0 } || 0.0
  rescue
    0.0
  end
end
