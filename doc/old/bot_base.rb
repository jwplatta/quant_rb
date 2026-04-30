# frozen_string_literal: true

require 'dotenv'
require 'pqueue'

Dotenv.load

class BotBase
  CHECK_INTERVAL = 5 # seconds
  TRADES_DIR = ENV.fetch('TRADES_DIR', 'data/trades')

  attr_reader :event_queue, :poller, :handler, :trade_file_mutex, :trade

  def initialize
    Dir.mkdir(TRADES_DIR) unless Dir.exist?(TRADES_DIR)

    # @event_queue = PQueue.new { |a, b| a.timestamp < b.timestamp }
    @event_queue = Queue.new
    @trade_file_mutex = Mutex.new
    @trade = nil

    @poller = MarketPoller.new(self, @event_queue, CHECK_INTERVAL)
    @handler = EventHandler.new(self, @event_queue)
    @threads = []
  end

  def run
    puts "Starting #{self.class.name} bot..."

    @threads << Thread.new { handler.run }
    @threads << Thread.new { poller.run }

    begin
      @threads.each(&:join)
    rescue Interrupt
      puts "Interrupt received, stopping #{self.class.name} bot..."
      poller.stop
      handler.stop
    ensure
      puts "Ensuring #{self.class.name} bot cleanup..."
      poller.stop
      handler.stop
    end
  end

  # def stop
  #   puts "Stopping #{self.class.name} bot..."
  #   # poller.stop
  #   handler.stop
  # end

  def read_trade
    trade_file_mutex.synchronize do
      trade = File.open(trade_file, 'r') do |file|
        JSON.parse(file.read, symbolize_names: true).then do |trade_hash|
          trade_class.from_h(trade_hash)
        end
      end

      File.open(order_history_file, 'r') do |file|
        JSON.parse(file.read, symbolize_names: true).then do |history|
          trade.order_history_from_h(history)
        end
      end

      trade
    rescue Errno::ENOENT
      nil
    end
  end

  def save_trade(trade)
    trade_file_mutex.synchronize do
      File.open(trade_file, 'w') do |file|
        file.write(trade)
      end
    end
  end

  def delete_trade
    trade_file_mutex.synchronize do
      File.delete(trade_file) if File.exist?(trade_file)
      File.delete(order_history_file) if File.exist?(order_history_file)
    end
  end
end
