# frozen_string_literal: true

require_relative "quant_rb/version"
require_relative "quant_rb/constants"
require_relative "quant_rb/logging"
require_relative "quant_rb/option_expiration"

begin
  require "dotenv"
  Dotenv.load
rescue LoadError
  # dotenv not available
rescue Errno::ENOENT
  # .env file not found
end

module QuantRb
  class Error < StandardError; end

  # ── Configuration ──────────────────────────────────────────────────────────

  Config = Struct.new(
    :data_path,
    :options_subpath,
    :history_subpath,
    :market_timezone,
    :log_level,
    keyword_init: true
  ) do
    def initialize(
      data_path:        ENV.fetch("QUANT_RB_DATA_PATH", "~/.tickrake/data"),
      options_subpath:  ENV.fetch("QUANT_RB_OPTIONS_SUBPATH", "options/schwab"),
      history_subpath:  ENV.fetch("QUANT_RB_HISTORY_SUBPATH", "history/schwab"),
      market_timezone:  ENV.fetch("QUANT_RB_MARKET_TIMEZONE", "America/New_York"),
      log_level:        :info
    )
      super
    end
  end

  def self.config
    @config ||= Config.new
  end

  def self.configure
    yield config
    Logging.apply_config!
  end

  def self.logger
    Logging.logger
  end

  def self.logger=(new_logger)
    Logging.logger = new_logger
  end

  # ── Core data objects ─────────────────────────────────────────────────────

  require_relative "quant_rb/data_objects/candle"
  require_relative "quant_rb/data_objects/option"
  require_relative "quant_rb/data_objects/options_chain"
  require_relative "quant_rb/data_objects/quote"

  # ── Data layer ────────────────────────────────────────────────────────────

  require_relative "quant_rb/data/data_source"
  require_relative "quant_rb/data/option_chain_config"
  require_relative "quant_rb/data/adapters/tickrake_adapter"
  require_relative "quant_rb/data/pricing/black_scholes"
  require_relative "quant_rb/data/pricing/crr_binomial"
  require_relative "quant_rb/data/pricing/implied_volatility_solver"
  require_relative "quant_rb/data/validation/option_chain_validator"
  require_relative "quant_rb/data/loaders/csv_candle"
  require_relative "quant_rb/data/series/candle_series"
  require_relative "quant_rb/data/index/synthetic_options_chain_index"
  require_relative "quant_rb/data/synthetic/synthetic_chain_builder"
  require_relative "quant_rb/data/option_chain_source"

  # ── Reality modeling ──────────────────────────────────────────────────────

  require_relative "quant_rb/reality/cost_breakdown"
  require_relative "quant_rb/reality/slippage_model"
  require_relative "quant_rb/reality/null_slippage_model"
  require_relative "quant_rb/reality/constant_slippage_model"
  require_relative "quant_rb/reality/transaction_fee_model"
  require_relative "quant_rb/reality/zero_transaction_fee_model"
  require_relative "quant_rb/reality/per_spread_transaction_fee_model"
  require_relative "quant_rb/reality/fill_model"
  require_relative "quant_rb/reality/optimistic_fill_model"
  require_relative "quant_rb/reality/bid_ask_fill_model"

  # ── Engine ────────────────────────────────────────────────────────────────

  require_relative "quant_rb/engine/order"
  require_relative "quant_rb/engine/slice"
  require_relative "quant_rb/engine/portfolio"
  require_relative "quant_rb/engine/position"
  require_relative "quant_rb/engine/securities"
  require_relative "quant_rb/engine/date_rules"
  require_relative "quant_rb/engine/time_rules"
  require_relative "quant_rb/engine/scheduler"
  require_relative "quant_rb/engine/live_engine"

  # ── Brokers ───────────────────────────────────────────────────────────────

  require_relative "quant_rb/brokers/broker_adapter"
  require_relative "quant_rb/brokers/backtest_broker"
  require_relative "quant_rb/brokers/schwab_broker"
  require_relative "quant_rb/brokers/ib_broker"

  # ── Reporting ─────────────────────────────────────────────────────────────

  require_relative "quant_rb/reporting/trade_record"
  require_relative "quant_rb/reporting/metrics"
  require_relative "quant_rb/reporting/backtest_result"
  require_relative "quant_rb/reporting/backtest_output_writer"
  require_relative "quant_rb/reporting/progress_reporter"

  # ── Strategy base (last, depends on engine) ───────────────────────────────

  require_relative "quant_rb/engine/strategy_base"
  require_relative "quant_rb/engine/backtest_engine"

  # Public alias so users write: QuantRb::BacktestEngine.run(MyStrategy)
  BacktestEngine = Engine::BacktestEngine
end
