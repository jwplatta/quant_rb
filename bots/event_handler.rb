require 'date'
require_relative 'trade_event'
require_relative '../services/trades/null_trade'

class EventHandler
  attr_reader :bot, :queue, :thread

  def initialize(bot, queue)
    @bot = bot
    @queue = queue
    @running = false
  end

  def start
    @running = true
    @thread = Thread.new do
      while @running
        event = queue.pop
        handle_event(event)
      end
    end
  end

  def stop
    @running = false
    @thread.exit if @thread && @thread.alive?
  end

  private

  def handle_event(event)
    case event.type
    when :find_new_trade
      handle_find_new_trade
    when :order_filled
      handle_order_filled(event.payload[:trade])
    when :order_failed
      handle_order_failed(event.payload[:trade])
    when :check_market
      handle_check_market(event.payload[:trade])
    when :market_changed
      handle_market_changed(event.payload[:trade])
    when :exit_loss
      handle_exit_loss(event.payload[:trade])
    when :exit_profit
      handle_exit_profit(event.payload[:trade])
    # when :adjust
    #   handle_adjustment(event.payload[:trade])
    when :hold
      handle_hold(event.payload[:trade])
    when :error
      handle_error(event.payload[:error])
    end
  end

  def handle_find_new_trade
    expiration_date = bot.next_weekday(Date.today + 7)
    puts "Finding iron condor trade for #{expiration_date}"
    trade = bot.find_trade(expiration_date)

    if trade.is_a?(NullTrade)
      puts "No suitable trade found. Retrying in next poll cycle."
      return
    end

    trade.increment = 0.05
    trade.preview(order_instruction: :entry)

    if trade.order_status == "ACCEPTED"
      trade.open
      bot.save_trade(trade)
      puts "Entry order placed: #{trade.order_id}"
    else
      puts "Trade not accepted"
      puts trade.order_rejects
    end
  end

  def handle_order_filled(trade)
    puts "Order filled"
    bot.save_trade(trade)
  end

  def handle_order_failed(trade)
    puts "Order #{trade.order_status}, deleting and finding new trade"
    bot.file_mutex.synchronize do
      File.delete(bot.class::TRADE_FILE) if File.exist?(bot.class::TRADE_FILE)
    end
  end

  def handle_market_changed(trade)
    puts "Market conditions changed, replacing order"
    trade.replace(order_instruction: :entry)
    bot.save_trade(trade)
  end

  def handle_exit_loss(trade)
    puts "Exiting due to loss threshold"
    trade.close
    bot.file_mutex.synchronize do
      File.delete(bot.class::TRADE_FILE) if File.exist?(bot.class::TRADE_FILE)
    end
  end

  def handle_exit_profit(trade)
    puts "Exiting due to profit target"
    trade.close
    bot.file_mutex.synchronize do
      File.delete(bot.class::TRADE_FILE) if File.exist?(bot.class::TRADE_FILE)
    end
  end

  def handle_adjustment(trade)
    puts "Trade tested (risk status: #{trade.risk_status})"
    puts "Tested side delta: #{trade.delta}"

    adjusted_trade = bot.find_adjustment(trade, kwargs)

    if adjusted_trade.nil?
      puts "Unable to adjust trade, continuing to monitor"
    else
      until trade.filled?
        puts "Waiting for trade to fill..."
        sleep(10)
        trade.check_order_status
        trade.check_market
      end

      adjusted_trade.preview(order_instruction: :entry)
      if adjusted_trade.order_status == "ACCEPTED"
        adjusted_trade.send(order_instruction: :entry)
        bot.save_trade(adjusted_trade)
        puts "Adjusted trade placed"

        # Log the new trade details
        puts "Call spread: #{adjusted_trade.call_spread.short_leg.strike}/#{adjusted_trade.call_spread.long_leg.strike}"
        puts "Put spread: #{adjusted_trade.put_spread.short_leg.strike}/#{adjusted_trade.put_spread.long_leg.strike}"
        puts "Credit: #{adjusted_trade.credit_debit}"
      else
        puts "Adjusted trade not accepted"
        puts adjusted_trade.order_rejects
        bot.save_trade(trade)
      end
    end
  end

  def handle_close_trade(trade)
    trade.preview(order_instruction: :exit)

    if trade.order_status == "ACCEPTED"
      trade.close
    else
      puts trade.order_rejects
      # TODO: need add a new event the queue to fix the trade and resend
    end
  end

  def handle_hold(trade)
    puts "Holding trade"
  end

  def handle_error(error)
    puts "Error occurred: #{error.message}"
    puts error.backtrace.join("\n")
  end
end