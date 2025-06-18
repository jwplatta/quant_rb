# frozen_string_literal: true

# NOTE: think this should be used directly in the spx_weekly_trade script
# to check the progress of the poistion

class TradeMonitor
  attr_reader :profit_thresh, :loss_thresh, :green_delta, :yellow_delta

  def initialize(profit_thresh: 0.75, loss_thresh: -4.0, green_delta: 0.16, yellow_delta: 0.26)
    @profit_thresh = profit_thresh
    @loss_thresh = loss_thresh
    @green_delta = green_delta
    @yellow_delta = yellow_delta
  end

  def risk_status(trade)
    trade.check_market # NOTE: ref quoteable.rb

    if trade.delta.undefined? || trade.delta.nil?
      'UNKNOWN'
    elsif trade.delta < green_delta
      'GREEN'
    elsif trade.delta < yellow_delta
      'YELLOW'
    else
      'RED'
    end
  end

  def tested?(trade)
    risk_status(trade) == 'YELLOW'
  end

  def danger?(trade)
    risk_status == 'RED'
  end

  def exit?(trade)
    progress >= exit_threshold || progress <= max_loss
  end

  # def progress
  #   return nil unless filled_open_credit_debit

  #   (net_credit_debit - net_filled_open_credit_debit) / net_filled_open_credit_debit
  # end

  def progress(sell_profit, buy_price)
    target_profit = sell_profit * profit_thresh
    target_loss = -sell_profit * loss_thresh
    current_profit_or_loss = sell_profit + buy_price

    if current_profit_or_loss >= target_profit
      100
    elsif current_profit_or_loss <= target_loss
      -100
    else
      # Progress is between profit and loss
      # Calculate progress towards 75% profit
      if current_profit_or_loss > 0
        (current_profit_or_loss / target_profit) * 100
      else
        -(current_profit_or_loss / target_loss) * 100
      end
    end
  end
end
