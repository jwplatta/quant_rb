# frozen_string_literal: true

require 'securerandom'

module Platypi
  module Trades

    TRADE_STATUSES = {
      open: 'OPEN',
      exit: 'EXIT',
      preview_open: 'PREVIEW_OPEN',
      preview_exit: 'PREVIEW_EXIT',
      error: 'ERROR'
    }.freeze

    class Trade
      include Platypi::Orderable

      class << self
        def from_json(json_string)
          data = JSON.parse(json_string, symbolize_names: true)
          from_hash(data)
        end

        def from_hash(data)
          strategy = data[:strategy] ? create_strategy_from_hash(data[:strategy]) : nil

          trade = new(
            strategy: strategy,
            trade_id: data[:trade_id],
            status: data[:trade_status],
            preview: data[:preview] || false,
          )

          # Restore orderable state if present
          if data[:order]
            trade.restore_order_state(data[:order])
          end

          trade
        end

        # Convenience methods for loading trades
        def find_open_trades
          TradeJournal.load_open_trades
        end

        def find_closed_trades
          TradeJournal.load_closed_trades
        end

        def find_trade(trade_id)
          TradeJournal.load_trade(trade_id)
        end

        def trade_open?(trade_id)
          TradeJournal.trade_open?(trade_id)
        end

        def open_trade_count
          TradeJournal.open_trade_count
        end

        private

        def create_strategy_from_hash(strategy_data)
          case strategy_data[:type]
          when 'callspread'
            Platypi::CallSpread.from_hash(strategy_data)
          when 'putspread'
            Platypi::PutSpread.from_hash(strategy_data)
          when 'ironcondor'
            Platypi::IronCondor.from_hash(strategy_data)
          when 'nullstrategy'
            Platypi::NullStrategy.new
          else
            raise "Unknown strategy type: #{strategy_data[:type]}"
          end
        end
      end

      def initialize(strategy: nil, trade_id: nil, status: nil, preview: false)
        @strategy = strategy
        @trade_id = trade_id || SecureRandom.uuid
        @status = status
        @preview = preview
        @progress = TradeProgress.new
        @journal = TradeJournal.new(@trade_id)

        initialize_orderable
      end

      attr_reader :trade_id, :status, :preview, :strategy

      def set_strategy(strategy)
        @strategy = strategy
      end

      def open
        if preview
          @status = 'PREVIEW_OPEN'
          preview_order(@strategy, order_instruction: :open)
        else
          @status = 'OPEN'
          send_order(@strategy, order_instruction: :open)
        end
      ensure
        save
      end

      def exit
        if preview
          @status = 'PREVIEW_EXIT'
          preview_order(@strategy, order_instruction: :exit)
        else
          @status = 'EXIT'
          send_order(@strategy, order_instruction: :exit)
        end
      ensure
        save
      end

      def check_progress
        # This could check order status, update trade state, etc.
        # Save after any state changes
        save
      end

      def save
        @journal.save_trade(self)
      end

      def reload
        latest = @journal.load_trade
        if latest
          @status = latest.status
          @strategy = latest.instance_variable_get(:@strategy)
          @preview = latest.preview

          # Restore order state
          if latest.respond_to?(:order_id) && latest.order_id
            @order_id = latest.order_id
            @order_status = latest.order_status
            @order_instruction = latest.order_instruction
            @order_price = latest.order_price
            @order_fees = latest.order_fees
            @order_commission = latest.order_commission
            @order_rejects = latest.order_rejects
          end
        end
        self
      end

      def history
        @journal.trade_history
      end

      def open_state
        @journal.open_state
      end

      def delete
        @journal.delete_trade
      end

      def current_file_path
        @journal.current_file_path
      end

      def open?
        %w[OPEN PREVIEW_OPEN].include?(status)
      end

      def closed?
        %w[EXIT PREVIEW_EXIT ERROR].include?(status)
      end

      def to_h
        {
          trade_id: trade_id,
          trade_status: status,
          preview: preview,
          strategy: @strategy&.to_h,
          order: order_to_h,
          timestamp: Time.now.utc
        }
      end

      def to_json(*args)
        to_h.to_json(*args)
      end
    end
  end
end
