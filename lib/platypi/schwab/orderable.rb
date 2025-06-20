# frozen_string_literal: true

require_relative 'schwab'

module Platypi
  module Orderable
    include Schwab

    attr_reader :order, :order_id, :order_status, :order_rejects,
      :filled_order, :transactions, :order_instruction,
      :order_price, :order_fees, :order_commission

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

    def preview_order(strategy, order_instruction: :open)
      build_and_preview_order(
        order_instruction: order_instruction,
        **extract_strategy_kwargs(strategy, order_instruction: order_instruction)
      ).then do |order_preview|
        # Store preview data in the order instance variables for later access
        @order_id = order_preview.order_id
        @order_instruction = order_instruction
        @order_price = order_preview.price
        @order_fees = order_preview.fees
        @order_commission = order_preview.commission
        @order_status = order_preview.status
        @order_rejects = if order_preview.accepted?
                          []
                        else
                          order_preview.order_validation_result.rejects.map(&:activity_message)
                        end

        order_preview
      end
    end

    def replace_order(strategy, order_instruction: :open)
      return nil unless order_id

      build_and_replace_order(
        order_id,
        order_instruction: order_instruction,
        **extract_strategy_kwargs(strategy, order_instruction: order_instruction)
      ).then do |order|
        unless order.nil?
          @order_id = order.order_id
          @order_status = order.status
          @order = order
          @transactions = nil
        end
      end
    end

    def send_order(strategy, order_instruction: :open)
      build_and_place_order(
        order_instruction: order_instruction,
        **extract_strategy_kwargs(strategy, order_instruction: order_instruction)
      ).then do |order|
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

    def stop_order
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

    def order_to_h
      {
        order_id: order_id,
        order_instruction: order_instruction,
        order_status: order_status,
        order_price: order_price,
        order_fees: order_fees,
        order_commission: order_commission,
        order_datetime: order_entered_time,
        order_rejects: order_rejects,
      }
    end

    def preview_credit_debit
      order_price * 100
    end

    def preview_net_credit_debit
      order_price * 100 - order_fees - order_commission
    end

    private

    def extract_strategy_kwargs(strategy, order_instruction: :open)
      case strategy.type
      when 'callspread', 'putspread'
        {
          strategy_type: strategy.type,
          short_leg_symbol: strategy.short_leg.symbol,
          long_leg_symbol: strategy.long_leg.symbol,
          price: strategy_price(strategy, order_instruction),
          quantiy: strategy.quantity
        }
      when 'ironcondor'
        {
          strategy_type: strategy.type,
          put_short_symbol: strategy.put_spread.short_leg.symbol,
          put_long_symbol: strategy.put_spread.long_leg.symbol,
          call_short_symbol: strategy.call_spread.short_leg.symbol,
          call_long_symbol: strategy.call_spread.long_leg.symbol,
          price: strategy_price(strategy, order_instruction),
          quantity: strategy.quantity
        }
      else
        raise "Unsupported strategy type: #{strategy.type}"
      end
    end

    def strategy_price(strategy, order_instruction)
      if order_instruction == :open
        strategy.credit
      elsif order_instruction == :exit
        strategy.debit.abs
      else
        raise "Unsupported order instruction: #{order_instruction}"
      end
    end
  end
end
