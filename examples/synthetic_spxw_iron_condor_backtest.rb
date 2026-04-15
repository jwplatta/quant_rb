# frozen_string_literal: true

require "csv"
require_relative "../lib/quant_rb"
require_relative "../doc/reference/spxw_iron_condor_examples"

DATA_ROOT = File.expand_path(ENV.fetch("QUANT_RB_DATA_PATH", "~/.tickrake/data"))
HISTORY_CANDIDATES = %w[history/ibkr-paper history/ibkr history/schwab].freeze

def detect_history_subpath
  HISTORY_CANDIDATES.find do |subpath|
    %w[SPX_1min.csv VIX_1min.csv VIX9D_1min.csv].all? do |filename|
      File.exist?(File.join(DATA_ROOT, subpath, filename))
    end
  end or raise "Could not find SPX/VIX/VIX9D minute history under #{DATA_ROOT}"
end

def downsample_series(series, step_minutes:)
  sampled = series.to_a.select.with_index do |candle, index|
    index.zero? || ((candle.datetime.min % step_minutes).zero? && candle.datetime.sec.zero?)
  end
  sampled << series.to_a.last unless sampled.last == series.to_a.last
  QuantRb::Data::Series::CandleSeries.new(sampled.uniq)
end

def restrict_series_to_dates(series, start_date:, end_date:)
  candles = series.to_a.select do |candle|
    date = candle.datetime.to_date
    date >= start_date && date <= end_date
  end
  QuantRb::Data::Series::CandleSeries.new(candles)
end

QuantRb.configure do |config|
  config.data_path = DATA_ROOT
  config.history_subpath = detect_history_subpath
  config.log_level = ENV.fetch("QUANT_RB_LOG_LEVEL", "info")
end

history_path = QuantRb::Data::DataSource.history_path
full_spx_series = QuantRb::Data::Series::CandleLoader.load(symbol: "SPX", resolution: :minute, data_path: history_path)
strategy_spx_series = restrict_series_to_dates(
  full_spx_series,
  start_date: SyntheticSpxwIronCondorExample::START_DATE,
  end_date: SyntheticSpxwIronCondorExample::END_DATE
)
synthetic_index = QuantRb::Data::Index::SyntheticOptionsChainIndex.new(
  symbol: "SPXW",
  synthetic_builder: QuantRb::Data::Synthetic::SyntheticChainBuilder.new(
    spx_series: full_spx_series,
    vix_series: QuantRb::Data::Series::CandleLoader.load(symbol: "VIX", resolution: :minute, data_path: history_path),
    vix9d_series: QuantRb::Data::Series::CandleLoader.load(symbol: "VIX9D", resolution: :minute, data_path: history_path),
    vix1d_series: begin
      QuantRb::Data::Series::CandleLoader.load(symbol: "VIX1D", resolution: :minute, data_path: history_path)
    rescue ArgumentError
      nil
    end,
    underlying_symbol: "SPX"
  )
)

QuantRb.logger.info("Running synthetic SPXW iron condor example")
QuantRb.logger.info("data_root=#{QuantRb.config.data_path} history_path=#{QuantRb::Data::DataSource.history_path}")
QuantRb.logger.info("mode=explicit synthetic chain index")

result = QuantRb::BacktestEngine.run(
  SyntheticSpxwIronCondorExample,
  candle_series: { SPX: downsample_series(strategy_spx_series, step_minutes: 30) },
  options_chain_index: { SPXW_options: synthetic_index }
)

puts
puts result.summary
puts
puts "Completed trades"
result.trades.each do |trade|
  puts trade.to_h
end
