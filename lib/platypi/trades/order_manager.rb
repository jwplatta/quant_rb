require_relative '../schwab/schwab'

module Platypi
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

      def accepted?
        order_status == 'ACCEPTED' || @order&.status == 'ACCEPTED'
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
        build_and_preview_order(
          order_instruction: order_instruction,
          **extract_strategy_kwargs(strategy, order_instruction: order_instruction)
        )
      end

      def send_preview_order(strategy, order_instruction: :open)
        build_and_preview_order(
          order_instruction: order_instruction,
          **extract_strategy_kwargs(strategy, order_instruction: order_instruction)
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
          **extract_strategy_kwargs(strategy, order_instruction: order_instruction)
        ).then do |order|
          update_order_state_from_order(order, order_instruction) unless order.nil?
          order
        end
      end

      def send_order(strategy, order_instruction: :open)
        build_and_place_order(
          order_instruction: order_instruction,
          **extract_strategy_kwargs(strategy, order_instruction: order_instruction)
        ).then do |order|
          update_order_state_from_order(order, order_instruction)
          order
        end
      end

      def check_order_status
        return nil unless order_id

        get_order(order_id).then do |order|
          update_order_state_from_status_check(order)
          order
        end
      end

      def stop_order
        return nil unless order_id

        cancel_order(order_id).then do |success|
          reset_order_state if success
          success
        end
      end

      def last_order_to_h
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

      def restore_from_hash(order_data)
        @order_id = order_data[:order_id]
        @order_status = order_data[:order_status]
        @order_instruction = order_data[:order_instruction]&.to_sym if order_data[:order_instruction]
        @order_price = order_data[:order_price]
        @order_fees = order_data[:order_fees]
        @order_commission = order_data[:order_commission]
        @order_rejects = order_data[:order_rejects] || []
        # Note: @order, @filled_order, and @transactions would need to be reconstructed from full order data
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
        @transactions = []
      end

      def update_order_state_from_preview(order_preview, order_instruction)
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
      end

      def update_order_state_from_order(order, order_instruction)
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

      def update_order_state_from_status_check(order)
        @order_status = order.status
        @order = order

        case order.status
        when 'FILLED'
          @order = order
          @order_id = order.order_id
          @order_status = order.status
          # TODO: commission and fees
        when 'REJECTED', 'EXPIRED', 'CANCELED'
          @order_status = order.status
          @order_id = nil
        when 'PENDING_ACTIVATION', 'WORKING'
          @order_status = order.status
        else
          raise "Unknown order status: #{order.status}"
        end
      end

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
end