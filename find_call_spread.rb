require "pry"
require "dotenv"
require "schwab_rb"
require_relative "services/schwab/data_objects/option_chain"
require_relative "services/search/spread_finder"
require_relative "services/schwab/schwab"

Dotenv.load

symbol = "$SPX"
expiration_date = Date.today + 8
contract_type = "CALL"
puts "Searching for #{contract_type} spread on #{symbol} expiring on #{expiration_date}"

option_chain = Schwab.option_chain(
  symbol,
  strike_range: "OTM",
  to_date: expiration_date
)

finder = SpreadFinder.new(
  symbol: symbol,
  contract_type: contract_type,
  end_date: expiration_date,
  short_delta: 0.1,
  max_spread: 10.0,
  min_credit: 50.0,
  dist_from_strike: 0.001,
  min_open_interest: -1,
  option_chain: option_chain
)
best_trade = finder.search

binding.pry