require_relative 'bot_base'
require 'date'
require 'json'
require_relative 'trade_event'
require_relative 'market_poller'
require_relative 'event_handler'
require_relative '../services/search/iron_condor_finder'
require_relative '../services/trades/iron_condor'
require_relative '../services/trades/null_trade'

class WeeklySPX < BotBase
  UNDERLYING_SYMBOL = "$SPX"
  TRADE_FILE = "#{TRADE_DIR}/trade.json"
  ORDER_HISTORY_FILE = "#{TRADE_DIR}/order_history.json"

  attr_reader :loss_threshold, :profit_threshold, :max_spread,
              :min_credit, :short_delta, :dist_from_strike, :min_open_interest

  def initialize(
    max_spread: 10.0,
    min_credit: 100.0,
    short_delta: 0.09,
    dist_from_strike: 0.001,
    min_open_interest: -1,
    loss_threshold: -0.25,
    profit_threshold: 0.50
  )
    super
    @max_spread = max_spread
    @min_credit = min_credit
    @short_delta = short_delta
    @dist_from_strike = dist_from_strike
    @min_open_interest = min_open_interest
    @loss_threshold = loss_threshold
    @profit_threshold = profit_threshold
  end

  def trade_finder
    IronCondorFinder.new(
      symbol: symbol,
      end_date: next_weekday(Date.today + 7),
      short_delta: short_delta,
      max_spread: max_spread,
      min_credit: min_credit,
      dist_from_strike: dist_from_strike,
      min_open_interest: min_open_interest
    )
  end

  def next_weekday(date)
    case date.wday
    when 0 # Sunday
      date + 1
    when 6 # Saturday
      date + 2
    else
      date
    end
  end

  def trade_class
    IronCondor
  end

  def trade_file
    TRADE_FILE
  end

  def order_history_file
    ORDER_HISTORY_FILE
  end

  def determine_action(trade)
    progress = trade.progress || 0

    if progress <= loss_threshold
      "EXIT_LOSS", nil
    elsif progress >= profit_threshold
      "EXIT_PROFIT", nil
    elsif trade.call_spread.risk_status == "RED"
      "ADJUST", { tested_side: "CALL_SPREAD" }
    elsif trade.put_spread.risk_status == "RED"
      "ADJUST", { tested_side: "PUT_SPREAD" }
    else
      "HOLD", nil
    end
  end

  def market_conditions_changed?(trade)
    curr_credit_debit = trade.credit_debit
    trade.check_market
    difference = (trade.credit_debit - curr_credit_debit).abs
    difference > 0.05
  end

  def find_adjustment(trade, tested_side)
    expiration_date = trade.expiration_date

    # Determine which side is tested and which is untested
    tested_is_call = (tested_side == "CALL_SPREAD")

    # Start with default parameters but allowing for more aggressive delta on the untested side
    tested_delta = short_delta
    untested_delta = short_delta * 1.5  # More aggressive on the untested side
    current_credit = min_credit * 0.8   # Allow for slightly less credit initially

    puts "Searching for new iron condor with tested side delta <= #{tested_delta} and untested side delta <= #{untested_delta}"

    # Try to find a new trade with appropriate deltas and higher credit
    adjusted_trade = nil

    # Gradually loosen constraints
    5.times do |i|
      # Increase the delta we're willing to accept on the tested side
      adjusted_tested_delta = tested_delta + (i * 0.02)
      # Increase the delta we're willing to accept on the untested side (more aggressively)
      adjusted_untested_delta = untested_delta + (i * 0.04)

      puts "Try #{i+1}: tested delta <= #{adjusted_tested_delta}, untested delta <= #{adjusted_untested_delta}"

      # Custom parameters for IronCondorFinder based on which side is tested
      finder_params = {
        symbol: symbol,
        end_date: expiration_date,
        max_spread: max_spread,
        min_credit: current_credit,
        dist_from_strike: dist_from_strike,
        min_open_interest: min_open_interest
      }

      if tested_is_call
        # Call side is tested, so be more conservative on call delta, more aggressive on put delta
        finder_params[:call_short_delta] = adjusted_tested_delta
        finder_params[:put_short_delta] = adjusted_untested_delta
      else
        # Put side is tested, so be more conservative on put delta, more aggressive on call delta
        finder_params[:put_short_delta] = adjusted_tested_delta
        finder_params[:call_short_delta] = adjusted_untested_delta
      end

      # Search for a trade with these parameters
      candidate = IronCondorFinder.new(**finder_params).search

      if !candidate.is_a?(NullTrade)
        # Verify the new trade has sufficient credit and improves the tested side
        if candidate.credit_debit >= min_credit * 0.7
          old_tested_delta = tested_is_call ? trade.call_spread.delta.abs : trade.put_spread.delta.abs
          new_tested_delta = tested_is_call ? candidate.call_spread.delta.abs : candidate.put_spread.delta.abs

          if new_tested_delta < old_tested_delta
            puts "Found suitable adjustment with credit: #{candidate.credit_debit}"
            adjusted_trade = candidate
            break
          end
        end
      end

      # Reduce the minimum credit requirement for next attempt
      current_credit -= min_credit * 0.1
    end

    adjusted_trade
  end
end
