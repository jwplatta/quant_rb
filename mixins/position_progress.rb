# frozen_string_literal: true

module PositionProgress
  attr_reader :profit_thresh, :loss_thresh, :green_delta, :yellow_delta

  def init_progress(profit_thresh: 0.75, loss_thresh: -4.0, green_delta: 0.16, yellow_delta: 0.26)
    @profit_thresh = profit_thresh
    @loss_thresh = loss_thresh
    @green_delta = green_delta
    @yellow_delta = yellow_delta
  end

  def risk_status
    if delta.abs < green_delta
      'GREEN'
    elsif delta.abs < yellow_delta
      'YELLOW'
    else
      'RED'
    end
  end

  def tested?
    risk_status == 'YELLOW'
  end

  def danger?
    risk_status == 'RED'
  end

  def exit_progress(sell_profit, buy_price)
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
        # Calculate progress towards the 4x loss target
        -(current_profit_or_loss / target_loss) * 100
      end
    end
  end

end
