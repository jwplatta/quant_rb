# frozen_string_literal: true

require "spec_helper"

RSpec.describe QuantRb::Engine::BacktestEngine do
  let(:fixture_history_path) { QUANT_RB_FIXTURES_ROOT.join("history", "schwab").to_s }
  let(:fixture_options_path) { QUANT_RB_FIXTURES_ROOT.join("options", "schwab").to_s }

  around do |example|
    original_config = QuantRb.config.dup

    QuantRb.configure do |config|
      config.data_path = QUANT_RB_FIXTURES_ROOT.to_s
      config.history_subpath = "history/schwab"
      config.options_subpath = "options/schwab"
    end

    example.run
  ensure
    QuantRb.instance_variable_set(:@config, original_config)
  end

  let(:strategy_class) do
    Class.new(QuantRb::Strategy) do
      attr_reader :on_data_calls, :end_of_day_symbols

      def initialize
        set_start_date(2024, 1, 2)
        set_end_date(2024, 1, 2)
        set_cash(10_000)
        @spy = add_equity("SPY", resolution: :minute)
        @on_data_calls = 0
        @end_of_day_symbols = []
      end

      def on_data(slice)
        @on_data_calls += 1

        market_order(@spy, 1) if time == Time.parse("2024-01-02 14:31:00 UTC")
        market_order(@spy, -1) if time == Time.parse("2024-01-02 14:32:00 UTC")
      end

      def on_end_of_day(symbol)
        @end_of_day_symbols << symbol
      end
    end
  end

  it "runs a backtest end-to-end from configured data sources" do
    result = described_class.run(strategy_class)

    expect(result).to be_a(QuantRb::Reporting::BacktestResult)
    expect(result.initial_cash).to eq(10_000)
    expect(result.trades.size).to eq(1)
    expect(result.trades.first.pnl).to eq(1.25)
    expect(result.final_portfolio_value).to eq(10_001.25)
  end

  it "supports injected candle series for testability" do
    candle_series = QuantRb::Data::Series::CandleLoader.load(
      symbol: "SPY",
      resolution: :minute,
      data_path: fixture_history_path
    )

    result = described_class.run(strategy_class, candle_series: candle_series)

    expect(result.trades.size).to eq(1)
    expect(result.trades.first.entry_price).to eq(101.5)
  end

  it "fires on_end_of_day for subscribed symbols" do
    strategy = nil
    instrumented_strategy = Class.new(strategy_class) do
      class << self
        attr_accessor :instance
      end

      def self.build_for_engine(**kwargs)
        self.instance = super
      end
    end

    described_class.run(instrumented_strategy)
    strategy = instrumented_strategy.instance

    expect(strategy.on_data_calls).to eq(3)
    expect(strategy.end_of_day_symbols).to include(:SPY)
  end

  it "creates and advances a progress bar when stdout is a tty" do
    progress_reporter = instance_double(QuantRb::Reporting::ProgressReporter, increment: nil, finish: nil)
    expect(QuantRb::Reporting::ProgressReporter).to receive(:new).with(
      total: 3,
      title: kind_of(String),
      enabled: :auto
    ).and_return(progress_reporter)
    expect(progress_reporter).to receive(:increment).exactly(3).times
    expect(progress_reporter).to receive(:finish)

    described_class.run(strategy_class)
  end

  it "allows callers to disable progress output explicitly" do
    progress_reporter = instance_double(QuantRb::Reporting::ProgressReporter, increment: nil, finish: nil)
    expect(QuantRb::Reporting::ProgressReporter).to receive(:new).with(
      total: 3,
      title: kind_of(String),
      enabled: false
    ).and_return(progress_reporter)

    described_class.run(strategy_class, progress: false)
  end
end
