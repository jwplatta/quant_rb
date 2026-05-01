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

  it "automatically settles option spreads on the expiration day's final bar" do
    strategy = Class.new(QuantRb::Strategy) do
      def initialize
        set_start_date(2024, 1, 18)
        set_end_date(2024, 1, 19)
        set_cash(10_000)
        @spx = add_index("SPX", resolution: :"5min")
        @spxw = add_index_option("SPX", "SPXW", resolution: :"5min")
        @opened = false
      end

      def on_data(_slice)
        return if @opened
        return unless time == Time.parse("2024-01-18 20:55:00 UTC")

        combo_limit_order(
          [
            { symbol: "SPXW_2024-01-19_P_4900", quantity: -1, expiration_date: Date.new(2024, 1, 19), strike: 4900.0, put_call: QuantRb::PUT, underlying_symbol: "SPX" },
            { symbol: "SPXW_2024-01-19_P_4880", quantity: 1, expiration_date: Date.new(2024, 1, 19), strike: 4880.0, put_call: QuantRb::PUT, underlying_symbol: "SPX" }
          ],
          1,
          1.00
        )
        @opened = true
      end
    end

    candles = QuantRb::Data::Series::CandleSeries.new([
      QuantRb::DataObjects::Candle.new(datetime: Time.parse("2024-01-18 20:55:00 UTC"), open: 4950.0, high: 4955.0, low: 4945.0, close: 4950.0, volume: 0),
      QuantRb::DataObjects::Candle.new(datetime: Time.parse("2024-01-19 20:55:00 UTC"), open: 4875.0, high: 4880.0, low: 4870.0, close: 4875.0, volume: 0)
    ])
    short_put = QuantRb::DataObjects::Option.new(symbol: "SPXW_2024-01-19_P_4900", underlying_symbol: "SPX", strike: 4900.0, put_call: QuantRb::PUT, underlying_price: 4950.0, expiration_date: Date.new(2024, 1, 19), bid: 1.60, ask: 1.70, mark: 1.65)
    long_put = QuantRb::DataObjects::Option.new(symbol: "SPXW_2024-01-19_P_4880", underlying_symbol: "SPX", strike: 4880.0, put_call: QuantRb::PUT, underlying_price: 4950.0, expiration_date: Date.new(2024, 1, 19), bid: 0.45, ask: 0.55, mark: 0.50)
    chain = QuantRb::DataObjects::OptionsChain.new(symbol: "SPXW", put_opts: [short_put, long_put])
    option_index = instance_double("OptionIndex")
    allow(option_index).to receive(:chains_at).and_return({ Date.new(2024, 1, 19) => chain })

    result = described_class.run(
      strategy,
      candle_series: { SPX: candles },
      options_chain_index: { SPXW_options: option_index },
      progress: false
    )

    expect(result.trades.size).to eq(1)
    expect(result.trades.first.exit_time).to eq(Time.parse("2024-01-19 20:55:00 UTC"))
    expect(result.trades.first.exit_price).to eq(20.0)
  end

  it "cancels unfilled orders at end of day so later sessions can submit again" do
    strategy = Class.new(QuantRb::Strategy) do
      def initialize
        set_start_date(2024, 1, 18)
        set_end_date(2024, 1, 19)
        set_cash(10_000)
        @spx = add_index("SPX", resolution: :"5min")
        @spxw = add_index_option("SPX", "SPXW", resolution: :"5min")
        @submitted = []
      end

      def on_data(_slice)
        return unless time.hour == 20 && time.min == 55

        @submitted << time
        combo_limit_order(
          [
            { symbol: "SPXW_2024-01-19_P_4900", quantity: -1, expiration_date: Date.new(2024, 1, 19), strike: 4900.0, put_call: QuantRb::PUT, underlying_symbol: "SPX" },
            { symbol: "SPXW_2024-01-19_P_4880", quantity: 1, expiration_date: Date.new(2024, 1, 19), strike: 4880.0, put_call: QuantRb::PUT, underlying_symbol: "SPX" }
          ],
          1,
          99.0
        )
      end

      def submitted_times
        @submitted
      end
    end

    instrumented_strategy = Class.new(strategy) do
      class << self
        attr_accessor :instance
      end

      def self.build_for_engine(**kwargs)
        self.instance = super
      end
    end

    candles = QuantRb::Data::Series::CandleSeries.new([
      QuantRb::DataObjects::Candle.new(datetime: Time.parse("2024-01-18 20:55:00 UTC"), open: 4950.0, high: 4955.0, low: 4945.0, close: 4950.0, volume: 0),
      QuantRb::DataObjects::Candle.new(datetime: Time.parse("2024-01-19 20:55:00 UTC"), open: 4950.0, high: 4955.0, low: 4945.0, close: 4950.0, volume: 0)
    ])
    short_put = QuantRb::DataObjects::Option.new(symbol: "SPXW_2024-01-19_P_4900", underlying_symbol: "SPX", strike: 4900.0, put_call: QuantRb::PUT, underlying_price: 4950.0, expiration_date: Date.new(2024, 1, 19), bid: 1.60, ask: 1.70, mark: 1.65)
    long_put = QuantRb::DataObjects::Option.new(symbol: "SPXW_2024-01-19_P_4880", underlying_symbol: "SPX", strike: 4880.0, put_call: QuantRb::PUT, underlying_price: 4950.0, expiration_date: Date.new(2024, 1, 19), bid: 0.45, ask: 0.55, mark: 0.50)
    chain = QuantRb::DataObjects::OptionsChain.new(symbol: "SPXW", put_opts: [short_put, long_put])
    option_index = instance_double("OptionIndex")
    allow(option_index).to receive(:chains_at).and_return({ Date.new(2024, 1, 19) => chain })

    broker = QuantRb::Brokers::BacktestBroker.new
    described_class.run(
      instrumented_strategy,
      broker: broker,
      candle_series: { SPX: candles },
      options_chain_index: { SPXW_options: option_index },
      progress: false
    )

    expect(instrumented_strategy.instance.submitted_times).to eq([
      Time.parse("2024-01-18 20:55:00 UTC"),
      Time.parse("2024-01-19 20:55:00 UTC")
    ])
    expect(broker.pending_orders).to be_empty
  end
end
