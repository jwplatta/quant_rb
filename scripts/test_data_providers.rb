require "pry"
require_relative "../lib/options_trader"

# NOTE: possible DSL
# result = OptionsTrader.search do
#   data_provider: :schwab
#   strategy_type: "ironcondor"
#   underlying_symbol: "$SPX"
#   expiration_date: Date.parse("2025-09-11")
#   put_call: "ALL"
#   quantity: 1
#   expiration_type: "W"
# end


schwab_provider = OptionsTrader::DataProviders::Schwab::Markets.new
# markets_service = OptionsTrader::Services::Markets.new(provider: schwab_provider)
historical_service = OptionsTrader::Services::HistoricalMarkets.new(provider: schwab_provider)

# strategy = OptionsTrader::StrategySearchFactory.find(
#   markets_service: markets_service,
#   strategy_type: "ironcondor",
#   underlying_symbol: "$SPX",
#   expiration_date: Date.parse("2025-09-11"),
#   put_call: "ALL",
#   quantity: 1,
#   expiration_type: "W",
#   settlement_type: "P",
#   option_root: "SPXW",
#   short_delta: 0.07,
#   max_spread: 10.0,
#   min_credit: 50.0,
#   increment: 0.05
# )

symbol = '$SPX'
start_datetime = DateTime.parse("2025-01-01T00:00:00Z")
end_datetime = DateTime.parse("2025-09-01T00:00:00Z")

prices = historical_service.get_price_history_every_five_min(
  symbol: symbol,
  start_datetime: start_datetime,
  end_datetime: end_datetime
)

prices.candles.each do |c|
  puts "#{c.datetime} - #{c.open} - #{c.close} - #{c.high} - #{c.low}"
end