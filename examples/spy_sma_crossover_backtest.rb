# frozen_string_literal: true

require_relative "../lib/quant_rb"
require_relative "../doc/reference/spy_sma_crossover"

data_path = File.expand_path(ENV.fetch("QUANT_RB_DATA_PATH", "~/.tickrake/data"))
history_subpath =
  ENV.fetch("QUANT_RB_HISTORY_SUBPATH", nil) ||
  begin
    candidates = [
      "history/ibkr-paper",
      "history/ibkr",
      "history/schwab"
    ]
    candidates.find do |subpath|
      root = File.join(data_path, subpath)
      Dir.glob(File.join(root, "**", "SPY_1min.csv")).any?
    end || "history/schwab"
  end

QuantRb.configure do |config|
  config.data_path = data_path
  config.history_subpath = history_subpath
  config.options_subpath = ENV.fetch("QUANT_RB_OPTIONS_SUBPATH", "options/schwab")
end

series = QuantRb::Data::Series::CandleLoader.load(
  symbol: "SPY",
  resolution: :minute,
  data_path: QuantRb::Data::DataSource.history_path
)

first_date = series.first.first.datetime.to_date
last_date = series.last.first.datetime.to_date

strategy_class = Class.new(SpySmaCrossover) do
  define_method(:initialize) do
    super()
    set_start_date(first_date.year, first_date.month, first_date.day)
    set_end_date(last_date.year, last_date.month, last_date.day)
  end
end

result = QuantRb::BacktestEngine.run(strategy_class)

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
