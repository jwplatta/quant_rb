require "pry"
require "json"
require "dotenv"
require_relative "services/search/iron_condor_finder"
require_relative "services/schwab/schwab"
require_relative "services/schwab/orders/order_factory"
require_relative "services/trades/call_spread"
require_relative "services/trades/put_spread"
require_relative "services/trades/iron_condor"
require_relative "services/trades/null_trade"

Dotenv.load

TRADE_DIR = "data/trades"
TRADE_FILE = "#{TRADE_DIR}/trade.json"

def next_weekday(date)
  case date.wday
  when 0
    date + 1
  when 6
    date + 2
  else
    date
  end
end

def find_trade(symbol, expiration_date)
  option_chain = Schwab.option_chain(
    symbol,
    strike_range: "OTM",
    to_date: expiration_date
  ).then do |option_chain|
    IronCondorFinder.new(
      symbol: symbol,
      end_date: expiration_date,
      short_delta: 0.1,
      max_spread: 10.0,
      min_credit: 50.0,
      dist_from_strike: 0.001,
      min_open_interest: -1,
      option_chain: option_chain
    ).search
  end
end

def read_trade
  File.open(TRADE_FILE, "r") do |file|
    JSON.parse(file.read, symbolize_names: true).then do |trade_hash|
      IronCondor.from_h(trade_hash)
    end
  end
rescue Errno::ENOENT
  NullTrade.new
end

def save_trade(trade)
  if File.exist?(TRADE_FILE)
    puts "Do you want to delete the existing trade? (yes/no)"
    answer = gets.chomp.downcase
    return unless answer == "yes"

    File.delete(TRADE_FILE)
  end

  File.open(TRADE_FILE, "w") do |file|
    file.write(trade.to_json)
  end
end

def send_order(trade)
  OrderFactory.build(
    trade,
    quantity: 1,
    account_number: ENV["SCHWAB_ACCOUNT_NUMBER"]
  ).then do |order|
    Schwab.preview_order(order)
  end
end

underlying_symbol = "$SPX"
expiration_date = next_weekday(Date.today + 7)
trade = find_trade(underlying_symbol, expiration_date)
trade.increment = 0.05

if trade
  order = send_order(trade)

  if order.accepted?
    trade.open_date = Date.today
    trade.open_credit_debit = trade.credit_debit
    trade.open_fees = order.fees
    trade.open_commission = order.commission
    save_trade(trade)
  else
    puts "Order not accepted"
  end
end

binding.pry

# Order
# - trade_id
# - order_id

# Transaction
# - trade_id
# - transaction_id
# - order_id


# 1. Find an iron condor that will be in the IronConder class
# Wrapped in the IronCondor class is a PutSpread and a CallSpread
# The OrderFactory turns the IronCondor into an order that can be submitted to Schwab
# Schwab with return and order_id
# wait until the order is filled before creating the Trade
# - set a timeout time and cancel the trade if it doesn't fill or if it's no longer favorable
# Once the order is filled, then save the Trade and the TradePositions to the database

# while True
  # Look up open trades or trades that have open positions
  # is there a trade on or not? - read the trades from the database or a file
  # if no trade is on, then find a trade
  # else check trade

  # if the trade can be exited, then send an exit order

  # if the trade is at risk, then can it be adjusted?

  # if the trade has hit the loss threshold, then send an exit order
  # exit
# end