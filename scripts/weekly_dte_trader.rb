# frozen_string_literal: true

require 'pry'
require 'json'
require 'dotenv'
require_relative '../services/search/iron_condor_finder'
require_relative '../services/trades/call_spread'
require_relative '../services/trades/put_spread'
require_relative '../services/trades/iron_condor'
require_relative '../services/trades/null_trade'

Dotenv.load

UNDERLYING_SYMBOL = '$SPX'
TRADE_DIR = 'data/trades'
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

def find_trade(expiration_date)
  IronCondorFinder.new(
    symbol: UNDERLYING_SYMBOL,
    end_date: expiration_date,
    short_delta: 0.09,
    max_spread: 10.0,
    min_credit: 55.0,
    dist_from_strike: 0.001,
    min_open_interest: -1
  ).search
end

def read_trade
  File.open(TRADE_FILE, 'r') do |file|
    JSON.parse(file.read, symbolize_names: true).then do |trade_hash|
      IronCondor.from_h(trade_hash)
    end
  end
rescue Errno::ENOENT
  nil
end

def save_trade(trade)
  File.open(TRADE_FILE, 'w') do |file|
    file.write(trade.to_json)
  end
end

trade = read_trade

if trade.nil?
  expiration_date = next_weekday(Date.today + 7)
  puts "Finding trade for #{expiration_date}"

  trade = find_trade(expiration_date)
  trade.increment = 0.05
  trade.preview(order_instruction: :entry)
  # trade.preview(order_instruction: :exit)

  if trade.order_status == 'ACCEPTED'
    save_trade(trade)
  else
    puts 'Trade not accepted'
    puts trade.order_rejects
    exit 0
  end
end

binding.pry
exit 0

loop do
  trade.check_market

  case trade.action
  when 'EXIT_LOSS'
    puts 'Exiting'
    trade.send
  when 'EXIT_PROFIT'
    puts 'Exiting'
  when 'HOLD'
    puts 'Holding'
  end
end

# NOTES:
# Implementing a weekly dte trader bot that sells options on the $SPX index that expire in 7 days. The bot should take as parameters the type of trade (call_spread, put_spread, iron_condor), the max spread, the min credit, the short delta, the distance from the strike, the minimum open interest, loss threshold, and profit theshold. The bot should be able to find a trade that meets the criteria and then send the order to Schwab. The bot should then monitor the trade and adjust it if necessary. The bot should also be able to exit the trade if it hits a loss threshold or a profit target.

# STEPS:
# - check if a trade is saved in the trade.json file in the data folder
# - if no trade, then use the appropriate finder in the services/search folder to find a new trade based on the trade type attr.
# - Use the trade.preview method to send the order to Schwab
# - If the order is accepted, then save the trade to the data/trade.json file
# - (when using the place_order method from the schwab mixin, you will need to wait for the trade to actually execute. here we will need some logic to regularly check whether the order has been filled and if it hasn't been filled, check the market conditinos and determine whether to replace the order with a new one.)
# - Then start monitoring the trade. You might want to separate the monitoring logic into a separate class
# - Every 5 minutes, check the market (I think there's a #check_market on the trade object) of the options
# - then inside the weekly_dte bot you should determine what action to take based on the market conditions.
# - If the trade is at a loss threshold, then send an exit order
# - If the trade is at a profit threshold, then send an exit order
# - If the trade is at risk (risk levels are determined inside the call_option and put_option classes), then try to adjust the trade (you might want to create a separate module for adjusting trades).

# NOTES for adjusting:
# symbols of the short legs on the trade and then use the quote method from the schwab
# mixin to get the latest deltas of these options
# If one of the short legs is tested. Then we will need to adjust the trade by trying to find a new iron condor that is
# whose deltas are better. Consider a side to be tested if the absolute value of the delta goes above 0.3.
# To find adjust the trade try to find a new iron condor that has net credit whose deltas are better than the current trade.
# Start by trying to find a new iron condor that whose short leg deltas are 0.1 or lower. If that fails, then begin
# adjusting the both the credit_debit lower to try to find a trade and increase the delta parameter on the tested short leg
# in the iron_condor_finder.rb. Be willing to adjust the trade until the credit_debit goes all the way down to zero.
# Once a new trade is found, then create a closing order for the existing trade and a new order for the new trade and send both.
# Then start monitoring again

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
