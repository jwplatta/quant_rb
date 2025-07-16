# frozen_string_literal: true

module OptionsTrader
  class TradeProgress
    def initialize(profit_thresh: 0.65, loss_thresh: -2.0)
      @profit_thresh = profit_thresh
      @loss_thresh = loss_thresh
      @progress_perc = nil
      @current_pnl = nil
    end

    attr_reader :profit_thresh, :loss_thresh, :progress_perc, :current_pnl

    def exit?(strategy, trade_history=[])
      raise ArgumentError, 'Strategy must be provided' if strategy.nil?

      check_progress(strategy, trade_history)

      progress_perc >= 100 || progress_perc <= -100
    end

    def check_progress(strategy, trade_history)
      strategy.check_market
      current_value = strategy.credit * strategy.quantity * 100.0

      total_credit = calculate_total_credit(trade_history)

      @current_pnl = total_credit - current_value

      # Calculate target profit and loss thresholds
      max_profit = total_credit.abs * profit_thresh
      max_loss = total_credit.abs * loss_thresh.abs

      @progress_perc = if current_pnl >= max_profit
        100.0
      elsif current_pnl <= -max_loss
        -100.0
      elsif current_pnl > 0
        (current_pnl / max_profit) * 100.0
      else
        (current_pnl / max_loss) * 100.0
      end

      @progress_perc
    end

    def to_h
      {
        progress_perc: progress_perc,
        current_pnl: current_pnl,
        profit_thresh: profit_thresh,
        loss_thresh: loss_thresh
      }
    end

    def from_h(data)
      @progress_perc = data[:progress_perc]
      @current_pnl = data[:current_pnl]
      @profit_thresh = data[:profit_thresh] if data[:profit_thresh]
      @loss_thresh = data[:loss_thresh] if data[:loss_thresh]
    end

    private

    def calculate_total_credit(trade_history)
      total_credits = 0.0
      total_fees = 0.0
      total_commissions = 0.0

      trade_history.each do |event|
        order_manager = event.order_manager
        quantity = event.strategy.quantity

        if opening_event?(event)
          price = order_manager.order_price || 0.0
          fees = order_manager.order_fees || 0.0
          commission = order_manager.order_commission || 0.0

          total_credits += (price * quantity * 100)
          total_fees += fees
          total_commissions += commission
        elsif closing_event?(event)
          price = order_manager.order_price || 0.0
          fees = order_manager.order_fees || 0.0
          commission = order_manager.order_commission || 0.0

          total_credits -= (price * quantity * 100)
          total_fees += fees
          total_commissions += commission
        end
      end

      total_credits - total_fees - total_commissions
    end

    def opening_event?(event)
      %w[TRADE_ENTERED ADJUST_ENTERED].include?(event.current_state)
    end

    def closing_event?(event)
      event.current_state == 'ADJUST_EXITED' || event.current_state == 'TRADE_EXITED'
    end
  end
end
