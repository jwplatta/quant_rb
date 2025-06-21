# frozen_string_literal: true

module Platypi
  class TradeProgress
    attr_reader :profit_thresh, :loss_thresh, :green_delta, :yellow_delta

    def initialize(profit_thresh: 0.65, loss_thresh: -4.0, green_delta: 0.16, yellow_delta: 0.26)
      @profit_thresh = profit_thresh
      @loss_thresh = loss_thresh
      @green_delta = green_delta
      @yellow_delta = yellow_delta
    end

    def risk_status(strategy)
      strategy.check_market # NOTE: ref quoteable.rb

      # Check if delta is nil first, then check if it responds to undefined? and is undefined
      if strategy.delta.nil? || (strategy.delta.respond_to?(:undefined?) && strategy.delta.undefined?)
        'UNKNOWN'
      elsif strategy.delta.abs < green_delta
        'GREEN'
      elsif strategy.delta.abs < yellow_delta
        'YELLOW'
      else
        'RED'
      end
    end

    def tested?(trade)
      risk_status(trade) == 'YELLOW'
    end

    def danger?(trade)
      risk_status(trade) == 'RED'
    end

    def exit?(trade)
      progress_value = progress(trade)
      return false unless progress_value

      progress_value >= 100 || progress_value <= -100
    end

    def progress(trade)
      open_state = trade.open_state
      return nil unless open_state

      current_strategy = trade.strategy
      return nil unless current_strategy

      current_strategy.check_market
      quantity = current_strategy.quantity || 1
      current_value = current_strategy.credit * current_strategy.quantity * 100.0
      opening_credit = open_credit(open_state)

      current_pnl = opening_credit - current_value

      # Calculate target profit and loss thresholds
      max_profit = opening_credit.abs * profit_thresh
      max_loss = opening_credit.abs * loss_thresh.abs

      # Return progress percentage
      if current_pnl >= max_profit
        100.0
      elsif current_pnl <= -max_loss
        -100.0
      elsif current_pnl > 0
        (current_pnl / max_profit) * 100.0
      else
        (current_pnl / max_loss) * 100.0
      end
    end

    def open_credit(trade_state)
      opening_price = trade_state.order_price || 0.0
      opening_fees = trade_state.order_fees || 0.0
      opening_commission = trade_state.order_commission || 0.0
      quantity = trade_state.strategy.quantity || 1

      # REVIEW: do we need to multiply by quantity?
      (opening_price * quantity * 100) - opening_fees - opening_commission
    end
  end
end
