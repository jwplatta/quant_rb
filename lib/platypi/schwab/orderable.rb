# frozen_string_literal: true

require_relative 'schwab'

module Platypi
  module Orderable
    include Schwab

    attr_reader :order, :order_id, :order_status, :order_rejects,
      :filled_order, :transactions, :order_instruction,
      :order_price, :order_fees, :order_commission,
      :order_preview, :order_preview_id, :order_preview_price,
      :order_preview_fees, :order_preview_commission,
      :order_preview_status, :order_preview_rejects, :order_preview_datetime,
      :order_preview_instruction

    def initialize_orderable
      @filled_order = nil
      @order = nil
      @order_id = nil
      @order_status = nil
      @order_price = nil
      @order_fees = nil
      @order_commission = nil
      @order_instruction = nil
      @order_rejects = []
      @transactions = []
      @order_preview = nil
      @order_preview_id = nil
      @order_preview_price = nil
      @order_preview_fees = nil
      @order_preview_commission = nil
      @order_preview_status = nil
      @order_preview_rejects = []
      @order_preview_datetime = nil
      @order_preview_instruction = nil
      @last_event = nil
    end

    def preview_net_credit_debit
      order_preview_price * 100 - order_preview_fees - order_preview_commission
    end

    def preview_credit_debit
      order_preview_price * 100
    end

    def order_id=(id)
      @order_id = id
    end

    def order_status
      order&.status || @order_status || 'UNKNOWN'
    end

    def order_entered_time
      @order&.entered_time
    end

    def order_transactions
      @transactions = transactions(
        start_date: order.order_date, # REVIEW: set to beginning of day
        transaction_types: ['TRADE']
      ).select do |t|
        t.order_id == order_id
      end
    end

    def accepted?
      order_status == 'ACCEPTED' || @filled_order&.status == 'ACCEPTED'
    end

    def filled?
      order_status == 'FILLED' || @filled_order&.status == 'FILLED'
    end

    def working?
      order_status == 'WORKING' || order_status == 'PENDING_ACTIVATION'
    end

    def failed?
      %w[REJECTED EXPIRED CANCELED].include?(order_status)
    end

    def preview(order_instruction: :open)
      build_and_preview_order(
        self,
        quantity: quantity,
        order_instruction: order_instruction
      ).then do |order_preview|
        @order_preview = order_preview
        @order_preview_id = order_preview.order_id
        @order_preview_instruction = order_instruction
        @order_preview_price = order_preview.price
        @order_preview_fees = order_preview.fees
        @order_preview_commission = order_preview.commission
        @order_preview_status = order_preview.status
        @order_preview_datetime = order_preview.entered_time
        @order_preview_rejects = if order_preview.accepted?
                           []
                         else
                           order_preview.order_validation_result.rejects(&:activity_message)
                         end
      end
    end

    def replace(order_instruction: :open)
      return nil unless order_id

      build_and_replace_order(order_id, self, quantity: quantity, order_instruction: order_instruction).then do |order|
        unless order.nil?
          @order_id = order.order_id
          @order_status = order.status
          @order = order
          @transactions = nil
        end
      end
    end

    def open
      send(order_instruction: :open)
    end

    def close
      send(order_instruction: :exit)
    end

    def send(order_instruction: :open)
      # REVIEW: self and quantity comes from the class that mixes in Orderable
      build_and_place_order(self, quantity: quantity, order_instruction: order_instruction).then do |order|
        @order_instruction = order_instruction

        if order.nil?
          @order_status = 'REJECTED'
        else
          @order_id = order.order_id
          @order_status = order.status
          @order = order
          @transactions = nil
        end
      end
    end

    def check_order_status
      return nil unless order_id

      get_order(order_id).then do |order|
        @order_status = order.status
        @order = order

        if order.status == 'FILLED'
          @filled_order = order
          @order_id = order.order_id
          @order_status = order.status
          # TODO: commission and fees
        elsif %w[REJECTED EXPIRED CANCELED].include?(order.status)
          @order_status = order.status
          @order_id = nil
        elsif %w[PENDING_ACTIVATION WORKING].include?(order.status)
          @order_status = order.status
        else
          raise "Unknown order status: #{order.status}"
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
          @order_instruction = nil
          @transactions = nil
        end
      end
    end
  end
end
