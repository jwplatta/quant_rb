require "pry"
require "dotenv"
require "schwab_rb"
require_relative "services/search/iron_condor_finder"
require_relative "services/schwab/schwab"
require_relative "services/schwab/orders/order_factory"

Dotenv.load

symbol = "$SPX"
expiration_date = Date.today + 8
puts "Searching for iron condor on #{symbol} expiring on #{expiration_date}"

option_chain = Schwab.option_chain(
  symbol,
  strike_range: "OTM",
  to_date: expiration_date
)

finder = IronCondorFinder.new(
  symbol: symbol,
  end_date: expiration_date,
  short_delta: 0.1,
  max_spread: 10.0,
  min_credit: 50.0,
  dist_from_strike: 0.001,
  min_open_interest: -1,
  option_chain: option_chain
)
trade = finder.search

binding.pry

puts """
###
Symbols: #{trade.symbols}
Expiration date: #{expiration_date}
Trade Credit: #{trade.credit_debit}
#{trade.credit_debit_5_increment}
###
Call Credit: #{trade.call_spread.credit_debit}
#{trade.call_spread.credit_debit_5_increment}
Call spread short strike: #{trade.call_spread.short_leg.strike}
Call spread long strike: #{trade.call_spread.long_leg.strike}
###
Put Credit: #{trade.put_spread.credit_debit}
#{trade.put_spread.credit_debit_5_increment}
Put spread short strike: #{trade.put_spread.short_leg.strike}
Put spread long strike: #{trade.put_spread.long_leg.strike}
"""

exit unless trade

order = OrderFactory.build(
  trade,
  quantity: 1,
  account_number: ENV["SCHWAB_ACCOUNT_NUMBER"]
)

order_preview = Schwab.preview_order(order)

binding.pry

if order_preview.order_strategy.status == "ACCEPTED"
  puts "Order preview successful. Sending order"
  # Schwab.place_order(order)
else
  puts "Order preview failed: #{order_preview.order_strategy.status}"
  binding.pry
end