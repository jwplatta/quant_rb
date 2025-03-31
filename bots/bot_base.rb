require "dotenv"
require 'thread'

Dotenv.load

class BotBase
  CHECK_INTERVAL = 300
  TRADE_DIR = "data/trades"

  attr_reader :event_queue, :poller, :handler, :file_mutex

  class << self
    def run
      new.run
    end
  end

  def initialize
    Dir.mkdir(TRADE_DIR) unless Dir.exist?(TRADE_DIR)

    @event_queue = Queue.new
    @file_mutex = Mutex.new

    @poller = MarketPoller.new(self, @event_queue, CHECK_INTERVAL)
    @handler = EventHandler.new(self, @event_queue)
  end

  def run
    puts "Starting #{self.class.name} bot..."
    trap("INT") { stop }
    trap("TERM") { stop }

    poller.start
    handler.start

    begin
      poller.thread.join
      handler.thread.join
    rescue Interrupt
      stop
    end
  end

  def stop
    puts "Stopping #{self.class.name} bot..."
    poller.stop
    handler.stop
  end

  def find_trade
    trade_finder.search
  end

  def read_trade
    file_mutex.synchronize do
      begin
        trade = File.open(trade_file, "r") do |file|
          JSON.parse(file.read, symbolize_names: true).then do |trade_hash|
            trade_class.from_h(trade_hash)
          end
        end

        File.open(order_history_file, "r") do |file|
          JSON.parse(file.read, symbolize_names: true).then do |history|
            trade.order_history_from_h(history)
          end
        end

        trade
      rescue Errno::ENOENT
        nil
      end
    end
  end

  def save_trade(trade)
    file_mutex.synchronize do
      File.open(trade_file, "w") do |file|
        file.write(trade.to_json)
      end

      File.open(order_history_file, "w") do |file|
        file.write(trade.order_history_to_h.to_json)
      end
    end
  end
end
