# frozen_string_literal: true

require_relative "../lib/quant_rb"
require_relative "../doc/reference/spxw_iron_condor_examples"

DATA_ROOT = File.expand_path(ENV.fetch("QUANT_RB_DATA_PATH", "~/.tickrake/data"))
HISTORY_CANDIDATES = %w[history/ibkr-paper history/ibkr history/schwab].freeze
OPTIONS_CANDIDATES = %w[options/schwab].freeze

def detect_history_subpath
  HISTORY_CANDIDATES.find do |subpath|
    File.exist?(File.join(DATA_ROOT, subpath, "SPX_1min.csv"))
  end or raise "Could not find SPX minute history under #{DATA_ROOT}"
end

def detect_options_subpath
  OPTIONS_CANDIDATES.find do |subpath|
    Dir.glob(File.join(DATA_ROOT, subpath, "SPXW_exp*.csv")).any?
  end or raise "Could not find SPXW sample chains under #{DATA_ROOT}"
end

QuantRb.configure do |config|
  config.data_path = DATA_ROOT
  config.history_subpath = detect_history_subpath
  config.options_subpath = detect_options_subpath
  config.log_level = ENV.fetch("QUANT_RB_LOG_LEVEL", "info")
end

QuantRb.logger.info("Running sampled SPXW iron condor example")
QuantRb.logger.info("data_root=#{QuantRb.config.data_path} history_path=#{QuantRb::Data::DataSource.history_path}")
QuantRb.logger.info("options_path=#{QuantRb::Data::DataSource.options_path} mode=sampled option chains")

result = QuantRb::BacktestEngine.run(SampledSpxwIronCondorExample)
saved_outputs = result.save(
  output_dir: ENV.fetch("QUANT_RB_BACKTEST_OUTPUT_DIR", QuantRb::Reporting::BacktestOutputWriter::DEFAULT_DIR),
  format: ENV.fetch("QUANT_RB_BACKTEST_FORMAT", "csv"),
  name: ENV["QUANT_RB_BACKTEST_NAME"]
)

puts
puts result.summary
puts "Saved summary: #{saved_outputs[:summary_path]}"
puts "Saved trades:  #{saved_outputs[:trades_path]}"
puts
puts "Completed trades"
result.trades.each do |trade|
  puts trade.to_h
end
