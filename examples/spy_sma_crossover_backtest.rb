# frozen_string_literal: true

require_relative "../lib/quant_rb"
require_relative "../doc/reference/spy_sma_crossover"

data_path = File.expand_path(ENV.fetch("QUANT_RB_DATA_PATH", "~/.tickrake/data"))

QuantRb.configure do |config|
  config.data_path = data_path
  config.history_subpath = ENV.fetch("QUANT_RB_HISTORY_SUBPATH", "history/ibkr-api")
  config.options_subpath = ENV.fetch("QUANT_RB_OPTIONS_SUBPATH", "options/schwab")
end

result = QuantRb::BacktestEngine.run(SpySmaCrossover)

puts result.summary
puts
puts "Trades"

result.trades.each do |trade|
  puts [
    trade.entry_time,
    trade.exit_time,
    trade.symbol,
    trade.quantity,
    trade.entry_price,
    trade.exit_price,
    trade.pnl
  ].join(" | ")
end
