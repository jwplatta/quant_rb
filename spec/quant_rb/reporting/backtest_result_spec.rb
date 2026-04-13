# frozen_string_literal: true

require "spec_helper"

RSpec.describe QuantRb::Reporting::BacktestResult do
  let(:trade) do
    QuantRb::Reporting::TradeRecord.new(
      id: "trade-1",
      strategy_class: "TestStrategy",
      symbol: "SPY",
      direction: :long,
      quantity: 1,
      entry_price: 100.0,
      exit_price: 102.0,
      entry_time: Time.parse("2024-01-02 14:31:00 UTC"),
      exit_time: Time.parse("2024-01-02 14:32:00 UTC"),
      legs: [{ symbol: :SPY, quantity: 1 }]
    )
  end

  subject(:result) do
    described_class.new(
      strategy_class: "TestStrategy",
      start_date: Date.new(2024, 1, 2),
      end_date: Date.new(2024, 1, 2),
      initial_cash: 10_000,
      final_portfolio_value: 10_002,
      trades: [trade]
    )
  end

  it "returns a non-empty summary" do
    expect(result.summary).to include("Backtest: TestStrategy", "Sharpe ratio")
  end

  it "serializes to a hash" do
    expect(result.to_h).to include(
      strategy_class: "TestStrategy",
      total_return: 0.02
    )
    expect(result.to_h[:metrics]).to include(:total_trades, :sharpe_ratio)
  end
end
