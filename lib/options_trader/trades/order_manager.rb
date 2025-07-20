require_relative '../schwab/schwab'

module OptionsTrader
  module Trades
    class OrderManager
      include Schwab

      attr_reader :order, :order_id, :order_status, :order_rejects,
                  :order_instruction, :order_price, :order_fees, :order_commission, :transactions

      def initialize(order_id: nil)
        @order_id = order_id
        @order = nil
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

      def opening?
        @order_instruction == :open
      end

      def closing?
        @order_instruction == :exit
      end

      def accepted?
        order_status == 'ACCEPTED' || @order&.status == 'ACCEPTED'
      end

      def paper_accepted?
        # NOTE: want to ignore oversold/overbought positions in paper trading
        oversold_regex = /in an oversold\/overbought position in your account/i
        order_status == 'ACCEPTED' || (order_status == 'REJECTED' && order_rejects.any? { |msg| oversold_regex.match?(msg) })
      end

      def filled?
        order_status == 'FILLED' || @order&.status == 'FILLED'
      end

      def working?
        order_status == 'WORKING' || order_status == 'PENDING_ACTIVATION'
      end

      def failed?
        %w[REJECTED EXPIRED CANCELED].include?(order_status)
      end

      def send_order_test(strategy, order_instruction: :open)
        order_preview = build_and_preview_order(
          order_instruction: order_instruction,
          **strategy.extract_kwargs(order_instruction)
        )
        order_preview.status == 'ACCEPTED'
      end

      def send_preview_order(strategy, order_instruction: :open)
        build_and_preview_order(
          order_instruction: order_instruction,
          **strategy.extract_kwargs(order_instruction)
        ).then do |order_preview|
          update_order_state_from_preview(order_preview, order_instruction)
          order_preview
        end
      end

      def replace_order(strategy, order_instruction: :open)
        return nil unless order_id

        build_and_replace_order(
          order_id,
          order_instruction: order_instruction,
          **strategy.extract_kwargs(order_instruction)
        ).then do |order|
          update_order_state_from_order(order, order_instruction)
          order
        end
      end

      def send_order(strategy, order_instruction: :open)
        build_and_place_order(
          order_instruction: order_instruction,
          **strategy.extract_kwargs(order_instruction)
        ).then do |order|
          update_order_state_from_order(order, order_instruction)
          order
        end
      end

      def check_order_status
        return nil unless order_id

        get_order(order_id).then do |order|
          @order_id = order.order_id
          @order_status = order.status
          @order = order

          if order.status == 'FILLED'
            @order_price = order.price
            @order_fees = order.fees
            @order_commission = order.commission
          end

          order
        end
      end

      def stop_working_order
        return nil unless order_id

        cancel_order(order_id).then do |success|
          reset_order_state if success
          success
        end
      end

      def to_s
        if order_rejects.any?
          "<ORDER #{order_id} | #{order_status} | #{order_rejects}>"
        else
          "<ORDER #{order_id} | #{order_status} | Price #{order_price} | Fees #{order_fees} | Commission #{order_commission}>"
        end
      end

      def to_h
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

      def from_h(order_data)
        @order_id = order_data[:order_id]
        @order_status = order_data[:order_status]
        @order_instruction = order_data[:order_instruction]
        @order_price = order_data[:order_price]
        @order_fees = order_data[:order_fees]
        @order_commission = order_data[:order_commission]
        @order_rejects = order_data[:order_rejects] || []
      end

      def preview_credit_debit
        order_price * 100
      end

      def preview_net_credit_debit
        order_price * 100 - order_fees - order_commission
      end

      private

      def reset_order_state
        @order = nil
        @order_id = nil
        @order_status = nil
        @order_price = nil
        @order_fees = nil
        @order_commission = nil
        @order_instruction = nil
        @order_rejects = []
      end

      def update_order_state_from_preview(order_preview, order_instruction)
        @order_id = order_preview.order_id
        @order = order_preview
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
      end

      def update_order_state_from_order(order, order_instruction)
        @order_instruction = order_instruction

        if order.nil?
          @order_status = 'REJECTED'
        else
          @order = order
          @order_id = order.order_id
          @order_status = order.status
          @order_price = order.price
          @order_fees = order.fees
          @order_commission = order.commission
        end
      end
    end
  end
end
