# frozen_string_literal: true

require 'securerandom'

module Platypi
  module Trades

    TRADE_STATES = {
      trade_found: 'TRADE_FOUND',
      no_trade_found: 'NO_TRADE_FOUND',
      open_order_sent: 'OPEN_ORDER_SENT',
      open_order_failed: 'OPEN_ORDER_FAILED',
      trade_entered: 'TRADE_ENTERED',
      trade_exited: 'TRADE_EXITED',
      close_order_failed: 'CLOSE_ORDER_FAILED',
      close_order_sent: 'CLOSE_ORDER_SENT',
      adjust_entered: 'ADJUST_ENTERED',
      adjust_open_order_sent: 'ADJUST_OPEN_ORDER_SENT',
      adjust_exited: 'ADJUST_EXITED',
      adjust_close_order_sent: 'ADJUST_CLOSE_ORDER_SENT',
      trade_open: 'TRADE_OPEN',
      send_order_error: 'SEND_ORDER_ERROR',
      trade_open_at_risk: 'TRADE_OPEN_AT_RISK'
    }.freeze

    class Trade
      class << self
        def from_json(json_string)
          data = JSON.parse(json_string, symbolize_names: true)
          from_h(data)
        end

        def from_h(data)
          strategy = data[:strategy] ? create_strategy_from_h(data[:strategy]) : nil

          trade = new(
            strategy: strategy,
            trade_id: data[:trade_id],
            paper_trading: data[:paper_trading] || false,
            timestamp: data[:timestamp] ? Time.parse(data[:timestamp].to_s) : nil,
            current_state: data[:trade_state] || TRADE_STATES[:no_trade_found],
            # Strategy attributes
            strategy_type: data[:strategy_type],
            underlying_symbol: data[:underlying_symbol],
            expiration_date: data[:expiration_date],
            short_delta: data[:short_delta] || 0.05,
            max_spread: data[:max_spread] || 10.0,
            min_credit: data[:min_credit] || 100.0,
            min_open_interest: data[:min_open_interest] || 0,
            dist_from_strike: data[:dist_from_strike] || 0.01,
            settlement_type: data[:settlement_type],
            option_root: data[:option_root],
            quantity: data[:quantity] || 1,
            # Trade management attributes
            profit_thresh: data[:profit_thresh] || 0.65,
            loss_thresh: data[:loss_thresh] || -2.0,
            green_delta: data[:green_delta] || 0.16,
            yellow_delta: data[:yellow_delta] || 0.26,
            strategy_adjuster: data[:strategy_adjuster] ? create_strategy_adjuster_from_h(data[:strategy_adjuster]) : nil
          )

          # Restore processing attributes
          trade.instance_variable_set(:@find_trade_attempts, data[:find_trade_attempts] || 0)
          trade.instance_variable_set(:@working_cnt, data[:working_cnt] || 0)

          # Restore order manager state if present
          if data[:order]
            trade.order_manager.from_h(data[:order])
          end

          # Restore progress state if present
          if data[:progress]
            trade.progress.from_h(data[:progress])
          end

          # Restore risk monitor state if present
          if data[:green_delta] || data[:yellow_delta]
            trade.risk_monitor.from_h(data)
          end

          trade
        end

        def trade_open?(trade_id)
          TradeJournal.trade_open?(trade_id)
        end

        def create_strategy_from_h(strategy_data)
          case strategy_data[:type]
          when 'callspread'
            Platypi::CallSpread.from_h(strategy_data)
          when 'putspread'
            Platypi::PutSpread.from_h(strategy_data)
          when 'ironcondor'
            Platypi::IronCondor.from_h(strategy_data)
          when 'nullstrategy'
            Platypi::NullStrategy.new
          else
            raise "Unknown strategy type: #{strategy_data[:type]}"
          end
        end

        def create_strategy_adjuster_from_h(adjuster_data)
          # This method should be implemented based on your strategy adjuster classes
          # For now, returning nil to avoid errors
          # You may need to implement this based on your specific strategy adjuster types
          nil
        end
      end

      def initialize(
        strategy: nil,
        strategy_type: nil,
        current_state: TRADE_STATES[:no_trade_found],
        trade_id: nil,
        paper_trading: false,
        profit_thresh: 0.65,
        loss_thresh: -2.0,
        green_delta: 0.16,
        yellow_delta: 0.26,
        strategy_adjuster: nil,
        timestamp: nil,
        underlying_symbol: nil,
        expiration_date: nil,
        short_delta: 0.05,
        max_spread: 10.0,
        min_credit: 100.0,
        min_open_interest: 0,
        dist_from_strike: 0.01,
        settlement_type: nil,
        option_root: nil,
        quantity: 1
      )
        @trade_id = trade_id || SecureRandom.uuid
        @strategy = strategy
        @strategy_adjuster = strategy_adjuster
        @current_state = current_state
        @paper_trading = paper_trading

        # NOTE: trade management components
        @progress = TradeProgress.new(profit_thresh: profit_thresh, loss_thresh: loss_thresh)
        @journal = TradeJournal.read_or_init(@trade_id)
        @order_manager = OrderManager.new
        @risk_monitor = RiskMonitor.new(green_delta: green_delta, yellow_delta: yellow_delta)

        # NOTE: processing attrs
        @find_trade_attempts = 0
        @working_cnt = 0
        @timestamp = timestamp

        # NOTE: strategy attrs
        @strategy_type = strategy.nil? ? strategy_type : strategy.type
        @underlying_symbol = underlying_symbol
        @expiration_date = expiration_date
        @short_delta = short_delta
        @max_spread = max_spread
        @min_credit = min_credit
        @min_open_interest = min_open_interest
        @dist_from_strike = dist_from_strike
        @settlement_type = settlement_type
        @option_root = option_root
        @quantity = quantity
      end

      attr_reader :trade_id, :paper_trading,
        :strategy, :order_manager, :journal,
        :current_state, :strategy_adjuster, :progress,
        :risk_monitor, :timestamp,
        :find_trade_attempts, :working_cnt

      def next
        if current_state == TRADE_STATES[:no_trade_found] || current_state == TRADE_STATES[:open_order_failed]
          find_strategy
        elsif current_state == TRADE_STATES[:close_order_failed]
          send_close_order
        elsif current_state == TRADE_STATES[:trade_found]
          send_open_order
        elsif current_state == TRADE_STATES[:open_order_sent]
          check_open_order
        elsif current_state == TRADE_STATES[:close_order_sent]
          check_close_order
        elsif current_state == TRADE_STATES[:adjust_open_order_sent]
          check_adjust_open_order
        elsif current_state == TRADE_STATES[:adjust_close_order_sent]
          check_adjust_close_order
        elsif current_state == TRADE_STATES[:adjust_exited]
          send_adjust_open_order
        elsif [TRADE_STATES[:trade_open], TRADE_STATES[:trade_entered], TRADE_STATES[:trade_open_at_risk]].include? current_state
          check_trade_progress_and_risk
        elsif current_state == TRADE_STATES[:trade_exited]
          # noop
        else
          raise "Unknown state: #{current_state}"
        end
      ensure
        @timestamp = Time.now.utc
        journal.log(self)
      end

      def exited?
        current_state == TRADE_STATES[:trade_exited]
      end

      def check_open_order
        @working_cnt += 1
        order_manager.check_order_status

        if strategy.market_change? && (order_manager.working? || order_manager.failed?)
          order_manager.stop_working_order
          find_strategy
        elsif order_manager.filled? || paper_trading
          @current_state = TRADE_STATES[:trade_entered]
        elsif order_manager.failed?
          @current_state = TRADE_STATES[:open_order_failed]
        elsif @order_manager.working?
          @current_state = TRADE_STATES[:open_order_sent]
        end
      end

      def check_close_order
        @working_cnt += 1
        order_manager.check_order_status

        if strategy.market_change? && (order_manager.working? || order_manager.failed?)
          order_manager.stop_working_order
          check_trade_progress_and_risk
        elsif order_manager.filled? || paper_trading
          @current_state = TRADE_STATES[:trade_exited]
        elsif order_manager.failed?
          @current_state = TRADE_STATES[:close_order_failed]
        elsif order_manager.working?
          @current_state = TRADE_STATES[:close_order_sent]
        end
      end

      def check_adjust_open_order
        @working_cnt += 1
        order_manager.check_order_status

        if strategy.market_change? && (order_manager.working? || order_manager.failed?)
          order_manager.stop_working_order
          send_adjust_open_order
        elsif order_manager.filled? || paper_trading
          @current_state = TRADE_STATES[:adjust_entered]
        elsif order_manager.working?
          @current_state = TRADE_STATES[:adjust_open_order_sent]
        end
      end

      def check_adjust_close_order
        @working_cnt += 1
        order_manager.check_order_status

        if strategy.market_change? && (order_manager.working? || order_manager.failed?)
          order_manager.stop_working_order
          check_trade_progress_and_risk
        elsif order_manager.filled? || paper_trading
          @current_state = TRADE_STATES[:adjust_exited]
        elsif @order_manager.working?
          @current_state = TRADE_STATES[:adjust_close_order_sent]
        end
      end

      def check_trade_progress_and_risk
        @working_cnt = 0

        if progress.exit?(self, journal)
          send_close_order
        elsif strategy_adjuster && risk_monitor.danger?(strategy) #NOTE: only adjust if we have an adjuster
          find_adjustment_and_send_close_order
        else
          @current_state = TRADE_STATES[:trade_open]
        end
      end

      def send_open_order
        send_preview_or_order(:open)
        @current_state = TRADE_STATES[:open_order_sent]
      rescue => e
        puts "Error opening trade #{trade_id}: #{e.message}"
        @current_state = TRADE_STATES[:send_order_error]
      end

      def send_close_order
        send_preview_or_order(:exit)
        @current_state = TRADE_STATES[:close_order_sent]
      rescue => e
        puts "Error exiting trade #{trade_id}: #{e.message}"
        @current_state = TRADE_STATES[:send_order_error]
      end

      def find_adjustment_and_send_close_order
        @adjustment = strategy_adjuster.find_new_strategy(strategy)

        unless @adjustment.nil?
          send_preview_or_order(:exit)
          @current_state = TRADE_STATES[:adjust_close_order_sent]
        else
          @current_state = TRADE_STATES[:trade_open_at_risk]
        end
      rescue => e
        puts "Error finding adjustment for trade #{trade_id}: #{e.message}"
        @current_state = TRADE_STATES[:send_order_error]
      end

      def send_adjust_open_order
        @strategy = @adjustment.new_strategy
        strategy.check_market
        send_preview_or_order(:open)
        @current_state = TRADE_STATES[:adjust_open_order_sent]
      rescue => e
        puts "Error opening trade #{trade_id}: #{e.message}"
        @current_state = TRADE_STATES[:send_order_error]
      end

      def send_preview_or_order(order_instruction)
        if paper_trading
          order_manager.send_preview_order(strategy, order_instruction: order_instruction)
        else
          order_manager.send_order(strategy, order_instruction: order_instruction)
        end
      end

      def find_strategy
        @strategy = strategy_finder_factory.search(
          strategy_type: @strategy_type,
          underlying_symbol: @underlying_symbol,
          expiration_date: @expiration_date,
          quantity: @quantity,
          settlement_type: @settlement_type,
          option_root: @option_root,
          from_date: @expiration_date,
          to_date: @expiration_date,
          short_delta: @short_delta,
          max_spread: @max_spread,
          min_credit: @min_credit,
          min_open_interest: @min_open_interest,
          dist_from_strike: @dist_from_strike
        )

        if strategy.nil?
          @find_trade_attempts += 1
          @current_state = TRADE_STATES[:no_trade_found]
        else
          @find_trade_attempts = 0
          @current_state = TRADE_STATES[:trade_found]
        end
      end

      # NOTE: Delegate methods to journal for convenience
      def trade_entered_event
        journal.trade_entered_event
      end

      def trade_exited_event
        journal.trade_exited_event
      end

      def trade_adjustment_events
        journal.trade_adjustment_events
      end

      def trade_history
        journal.trade_history
      end


      def to_h
        {
          trade_id: trade_id,
          paper_trading: paper_trading,
          trade_state: current_state,
          strategy: strategy&.to_h,
          order: order_manager.to_h,
          progress: progress.to_h,
          timestamp: timestamp,
          # Strategy attributes
          strategy_type: @strategy_type,
          underlying_symbol: @underlying_symbol,
          expiration_date: @expiration_date,
          short_delta: @short_delta,
          max_spread: @max_spread,
          min_credit: @min_credit,
          min_open_interest: @min_open_interest,
          dist_from_strike: @dist_from_strike,
          settlement_type: @settlement_type,
          option_root: @option_root,
          quantity: @quantity,
          # Trade management attributes
          profit_thresh: @progress.profit_thresh,
          loss_thresh: @progress.loss_thresh,
          green_delta: @risk_monitor.green_delta,
          yellow_delta: @risk_monitor.yellow_delta,
          strategy_adjuster: @strategy_adjuster&.to_h,
          # Processing attributes
          find_trade_attempts: @find_trade_attempts,
          working_cnt: @working_cnt
        }
      end

      def to_json
        to_h.to_json
      end

      def strategy_finder_factory
        Platypi::StrategyFinderFactory
      end
    end
  end
end
