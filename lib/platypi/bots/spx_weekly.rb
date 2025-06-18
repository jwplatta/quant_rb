require_relative '../services/search/call_spread_finder'
require_relative '../services/search/put_spread_finder'
require_relative '../services/trades/call_spread'
require_relative '../services/trades/put_spread'
require_relative '../services/trades/call_option'
require_relative '../services/trades/put_option'
require_relative '../mixins/schwab/schwab'

class TradeEvent
  def initialize(trade, event_type)
    @trade = trade
    @event_type = event_type
    @timestamp = Time.now.utc
  end

  attr_reader :trade, :event_type, :timestamp

  def to_h
    {
      trade_event: event_type,  # OPEN, CLOSE
      timestamp: timestamp
    }.merge(trade.to_h)
  end
end

class Trade
  def initialize(strategy, trade_id: nil, status: 'OPEN', preview: false)
    @trade_id = trade_id || SecureRandom.uuid
    @status = status # e.g., OPEN, CLOSED
    @strategy = strategy
    @preview = preview
    @events = []
  end
  attr_reader :strategy, :trade_id, :status, :events, :preview

  def to_h
    {
      trade_id: trade_id,
      trade_type: strategy.type, # e.g., CALL_SPREAD, PUT_SPREAD
      trade_status: status,
      underlying_symbol: strategy.underlying_symbol,
      order_id: preview ? strategy.order_preview_id : strategy.order_id,
      order_instruction: preview ? strategy.order_preview_instruction : strategy.order_instruction,
      price: preview ? strategy.order_preview_price : strategy.order_price,
      fees: preview ? strategy.order_preview_fees : strategy.order_fees,
      commission: preview ? strategy.order_preview_commission : strategy.order_commission,
      expiration_date: strategy.expiration_date,
      quantity: strategy.quantity,
      instruments: strategy..instruments,
    }
  end
end

class TradeHistory
  class << self
    def load
      new
    end
  end

  def initialize
    @file_path = './trade_history.jsonl'
    @trades = []
    @current_trade = nil

    load_trades
  end

  attr_reader :file_path, :trades, :current_trade

  def load_trades
    return [] unless File.exist?(@file_path)

    File.open(@file_path, 'r') do |file|
      file.each_line do |line|
        trade = JSON.parse(line, symbolize_names: true)
        @trades << trade

        if trade[:trade_status] == 'OPEN'
          @current_trade = trade
        end
      end
    end
  rescue JSON::ParserError => e
    puts "Error loading trades from #{@file_path}: #{e.message}"
    []
  end

  def save_trade(trade)
    @trades << trade

    File.open(@file_path, 'a') do |file|
      file.write(trade.to_json)
    end
  end

  def all_trades
    @trades
  end
end

class SPXWeekly
  include Schwab

  TRADE_FILE = "../tmp/spx_weekly_trade.json"
  DEBUG = ENV['DEBUG'] == 'true' || true

  def initialize
    @underlying_symbol = '$SPX'
    @option_root = 'SPXW'
    @settlement_type = 'P' # NOTE: PM settlement
    @trade_history = TradeHistory.load
  end

  attr_reader :underlying_symbol, :option_root, :settlement_type, :trade_history

  def run
    curr_trade = trade_history.current_trade

    if curr_trade.nil?
      puts "No current trade found. Entering new trade..."
      enter_trade
    else
      # NOTE: monitor existing trade
      binding.pry
      monitor_trade(curr_trade)
    end
  end

  def enter_trade
    exp_date = next_weekday
    opt_chain = option_chain(
      underlying_symbol,
      contract_type: 'CALL',
      from_date: exp_date,
      to_date: exp_date,
    )

    if opt_chain.nil?
      raise "No options chain found for #{underlying_symbol}"
    end

    new_trade = Services::Search::CallSpreadFinder.new(
      underlying_symbol: underlying_symbol,
      expiration_date: exp_date,
      short_delta: 0.07,
      max_spread: 25.0,
      min_credit: 105.0,
      min_open_interest: 0,
      dist_from_strike: 0.01,
      settlement_type: @settlement_type,
    ).search(opt_chain)

    if new_trade.is_a? Services::Trades::NullTrade
      puts "No suitable trade found for #{underlying_symbol}."
    else
      puts "Found trade: #{new_trade.short_leg.symbol} - #{new_trade.long_leg.symbol}"
      puts "Short leg strike: #{new_trade.short_leg.strike}, Long leg strike: #{new_trade.long_leg.strike}"
      puts "Credit: #{new_trade.credit}, Debit: #{new_trade.debit}"
      puts "Expiration date: #{new_trade.expiration_date}"

      new_trade.increment = 0.05
      new_trade.check_market
      new_trade.preview(order_instruction: :open)

      if new_trade.order_preview_status == 'ACCEPTED'
        # NOTE: if order preview is accepted, then open the trade
        puts "Order preview accepted. Opening trade..."
        new_trade.preview(order_instruction: :open)

        if DEBUG
          # NOTE: save trade and monitor it
          trade_history.save_trade(
            new_trade.to_event('OPEN', preview: true)
          )
          binding.pry
        end

        while true
          new_trade.check_order_status

          if new_trade.filled?
            puts "Trade filled: #{new_trade.short_leg.symbol} - #{new_trade.long_leg.symbol}"
            puts "Order ID: #{new_trade.order_id}"
            puts "Order status: #{new_trade.order_status}"
            monitor_trade(new_trade)
          elsif new_trade.market_change?
            puts "Market conditions changed. Rechecking trade..."
            new_trade.cancel
            enter_trade
          elsif new_trade.working?
            puts "Order is still working. Status: #{new_trade.order_status}"
            sleep 5
          else
            puts "Order not filled yet. Status: #{new_trade.order_status}"
            puts "Waiting for 5 seconds before checking again..."
            sleep 5
          end
        end
      else
        puts "Order preview not accepted. Status: #{new_trade.order_preview_status}"
        puts "Rejects: #{new_trade.order_preview_rejects.join(', ')}"
        enter_trade
      end
    end
  ensure
    puts "Trade process completed."

    new_trade.cancel if new_trade
  end

  def monitor_trade(trade)
    sleep_time, status = TradeMonitor.check(trade) == 'HOLD'

    case status
    when 'HOLD'
      puts "Trade is in HOLD status. Waiting for #{sleep_time} seconds..."
      sleep sleep_time
      monitor_trade(trade)
    when 'EXIT'
      puts "Trade is in EXIT status. Exiting trade..."
      exit_trade(trade)
    else
      raise "Unknown trade status: #{status}"
    end
  end

  def exit_trade(trade)

    trade.increment = 0.05
    trade.check_market
    trade.preview(order_instruction: :exit)

    binding.pry
  end

  private

  def next_weekday
    date = Date.today + 7

    case date.wday
    when 0 # Sunday
      date + 1
    when 6 # Saturday
      date + 2
    else
      date
    end
  end
end
