require_relative 'trade_event'

class MarketPoller
  attr_reader :bot, :queue, :interval, :thread

  def initialize(bot, queue, interval = 120)
    @bot = bot
    @queue = queue
    @interval = interval
    @running = false
  end

  def start
    @running = true
    @thread = Thread.new do
      while @running
        poll
        sleep(interval)
      end
    end
  end

  def stop
    @running = false
    @thread.exit if @thread && @thread.alive?
  end

  private

  def poll
    trade = bot.read_trade

    if trade.nil?
      queue.push(TradeEvent.new(:find_new_trade))
    elsif trade.filled?
      action = bot.determine_action(trade)
      queue.push(
        TradeEvent.new(
          action,
          { trade: trade }
        )
      )
    else
      trade.check_order_status

      if trade.filled?
        queue.push(TradeEvent.new(:order_filled, { trade: trade }))
      elsif trade.failed?
        queue.push(TradeEvent.new(:order_failed, { trade: trade }))
      elsif trade.working? && bot.market_conditions_changed?(trade)
        queue.push(TradeEvent.new(:market_changed, { trade: trade }))
      end
    end
  rescue => e
    queue.push(TradeEvent.new(:error, { error: e }))
  end
end
