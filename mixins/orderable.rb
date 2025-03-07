require_relative "schwab/schwab"

module Orderable
  include Schwab

  attr_reader :order_id, :order_status, :open_date,
    :open_credit_debit, :open_fees, :open_commission,
    :order_rejects, :transactions

  def order_id=(id)
    @order_id = id
  end

  def open_credit_debit=(credit_debit)
    @open_credit_debit = credit_debit
  end

  def open_date=(date)
    @open_date = date
  end

  def open_fees=(fees)
    @open_fees = fees
  end

  def open_commission=(commission)
    @open_commission = commission
  end

  def add_transaction(transaction)
    @transactions ||= [] if @transactions.nil?
    @transactions << transaction
  end

  def preview(position_type: :entry)
    build_and_preview_order(self, quantity: quantity, position_type: position_type).then do |order_preview|
      if order_preview.accepted?
        @open_date = Date.today
        @open_credit_debit = credit_debit
        @open_fees = order_preview.fees
        @open_commission = order_preview.commission
        @order_status = order_preview.order_strategy.status
        @order_rejects = []
      else
        @order_status = order_preview.order_strategy.status
        @order_rejects = order_preview.order_validation_result.rejects(&:activity_message)
      end
    end
  end

  def send(position_type: :entry)
    build_and_place_order(self, quantity: quantity, position_type: position_type).then do |order|
      unless order.nil?
        @order_id = order.order_id
        @open_date = Date.today
        @order_status = order.status
      end
    end
  end

  def filled?
    order_status == "FILLED"
  end

  def check_order_status
    return nil unless order_id

    get_order(order_id).then do |order|
      @order_status = order.status

      if order.status == "FILLED" and order_status != "FILLED"
        @order_id = order.order_id
        @order_status = order.status

        # STEP: might need to look these up from the transaction history
        @open_credit_debit = order.price
        @open_fees = nil
        @open_commission = nil
      elsif ["REJECTED", "EXPIRED", "CANCELED"].include? order.status
        @order_id = nil
        @order_status = order.status
        @open_date = nil
        @open_credit_debit = nil
        @open_fees = nil
        @open_commission = nil
      else ["PENDING_ACTIVATION", "WORKING"].include? order.status
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
        @open_date = nil
        @open_credit_debit = nil
        @open_fees = nil
        @open_commission = nil
      end
    end
  end

  def orderable_h
    {
      open_credit_debit: open_credit_debit,
      open_date: open_date,
      open_fees: open_fees,
      open_commission: open_commission,
    }
  end
end