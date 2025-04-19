require_relative "schwab/schwab"

module Orderable
  include Schwab

  attr_reader :order, :order_id, :order_status, :order_rejects, :filled_order, :transactions

  def initialize_orderable
    @filled_order = nil
    @order = nil
    @transactions = []
  end

  def order_id=(id)
    @order_id = id
  end

  def filled_credit_debit
    @filled_order&.price
  end

  def filled_order_id
    @filled_order&.order_id
  end

  def filled_order_status
    @filled_order&.status
  end

  def filled_order_price
    @filled_order&.price
  end

  def filled_order_date
    @filled_order&.entered_time&.to_date
  end

  def filled_open_date
    @filled_order&.entered_time&.to_date
  end

  def filled_open_credit_debit
    @filled_order&.price
  end

  def filled_open_fees
    @filled_order&.respond_to?(:fees) ? @filled_order.fees : nil
  end

  def filled_open_commission
    @filled_order&.respond_to?(:commission) ? @filled_order.commission : nil
  end

  def filled_order_transactions
    @transactions = transactions(
      start_date: filled_order_date,
      transaction_types: ["TRADE"]
    ).select do |t|
      t.order_id == filled_order_id
    end
  end

  def filled?
    order_status == "FILLED" || @filled_order&.status == "FILLED"
  end

  def working?
    order_status == "WORKING"
  end

  def failed?
    ["REJECTED", "EXPIRED", "CANCELED"].include?(order_status)
  end

  def preview(order_instruction: :entry)
    build_and_preview_order(
      self,
      quantity: quantity,
      order_instruction: order_instruction
    ).then do |order_preview|
      if order_preview.accepted?
        @order_status = order_preview.order_strategy.status
        @order_rejects = []
      else
        @order_status = order_preview.order_strategy.status
        @order_rejects = order_preview.order_validation_result.rejects(&:activity_message)
      end
    end
  end

  def replace(order_instruction: :entry)
    return nil unless order_id

    build_and_replace_order(order_id, self, quantity: quantity, order_instruction: order_instruction
    ).then do |order|
      unless order.nil?
        @order_id = order.order_id
        @order_status = order.status
        @order = order
      end
    end
  end

  def open
    send(order_instruction: :entry)
  end

  def close
    send(order_instruction: :exit)
  end

  def send(order_instruction: :entry)
    build_and_place_order(self, quantity: quantity, order_instruction: order_instruction).then do |order|
      unless order.nil?
        @order_id = order.order_id
        @order_status = order.status
        @order = order
      else
        @order_id = nil
        @order_status = "REJECTED"
      end
    end
  end

  def check_order_status
    return nil unless order_id

    get_order(order_id).then do |order|
      @order_status = order.status
      @order = order

      if order.status == "FILLED"
        # Store the filled order
        @filled_order = order

        # Keep the current order_id and status for reference
        @order_id = order.order_id
        @order_status = order.status
      elsif ["REJECTED", "EXPIRED", "CANCELED"].include?(order.status)
        @order_status = order.status
        @order_id = nil
      elsif ["PENDING_ACTIVATION", "WORKING"].include?(order.status)
        @order_status = order.status
      end
    end
  end

  def cancel
    return nil unless order_id

    cancel_order(order_id).then do |success|
      if success
        @order_id = nil
        @order_status = nil
        @order = nil
      end
    end
  end
end
