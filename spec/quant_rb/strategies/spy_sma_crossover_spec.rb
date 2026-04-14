# frozen_string_literal: true

require "spec_helper"
require_relative "../../../doc/reference/spy_sma_crossover"

RSpec.describe SpySmaCrossover do
  def build_candle_series(prices, start_time: Time.parse("2024-01-02 14:00:00 UTC"))
    candles = prices.each_with_index.map do |price, index|
      QuantRb::DataObjects::Candle.new(
        datetime: start_time + (index * 60),
        open: price,
        high: price,
        low: price,
        close: price,
        volume: 1_000
      )
    end

    QuantRb::Data::Series::CandleSeries.new(candles)
  end

  it "produces a complete trade with deterministic crossover timing" do
    prices = ([100.0] * 30) + ([110.0] * 10) + ([90.0] * 10)
    result = QuantRb::BacktestEngine.run(described_class, candle_series: build_candle_series(prices))

    expect(result.trades.size).to eq(1)

    trade = result.trades.first
    expect(trade.symbol).to eq(:SPY)
    expect(trade.quantity).to eq(100)
    expect(trade.entry_time).to eq(Time.parse("2024-01-02 14:30:00 UTC"))
    expect(trade.exit_time).to eq(Time.parse("2024-01-02 14:44:00 UTC"))
    expect(trade.entry_price).to eq(110.0)
    expect(trade.exit_price).to eq(90.0)
    expect(trade.pnl).to eq(-2_000.0)
    expect(result.final_portfolio_value).to eq(98_000.0)
    expect(result.metrics.to_h).to include(total_trades: 1, total_pnl: -2_000.0)
  end

  it "runs against local tickrake SPY minute data when available", :integration do
    history_path = File.expand_path("~/.tickrake/data/history/schwab")
    skip "tickrake SPY history not available" unless Dir.glob(File.join(history_path, "**", "SPY_1min.csv")).any?

    candle_series = QuantRb::Data::Series::CandleLoader.load(
      symbol: "SPY",
      resolution: :minute,
      data_path: history_path
    )
    first_date = candle_series.first.datetime.to_date
    last_date = candle_series.last.datetime.to_date

    strategy_class = Class.new(described_class) do
      define_method(:initialize) do
        super()
        set_start_date(first_date.year, first_date.month, first_date.day)
        set_end_date(last_date.year, last_date.month, last_date.day)
      end
    end

    result = QuantRb::BacktestEngine.run(strategy_class, candle_series: candle_series)

    expect(result).to be_a(QuantRb::Reporting::BacktestResult)
    expect(result.trades).not_to be_empty
    expect(result.final_portfolio_value).to be_a(Float)
  end
end
