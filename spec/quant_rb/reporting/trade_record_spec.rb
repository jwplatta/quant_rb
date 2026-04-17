# frozen_string_literal: true

require "spec_helper"

RSpec.describe QuantRb::Reporting::TradeRecord do
  let(:record) do
    described_class.new(
      id:             "test-001",
      strategy_class: Class.new,
      symbol:         "SPY",
      direction:      :buy,
      quantity:       100,
      entry_price:    450.0,
      exit_price:     460.0,
      entry_time:     Time.parse("2024-01-15T09:30:00Z"),
      exit_time:      Time.parse("2024-01-15T15:00:00Z"),
      legs:           []
    )
  end

  it "computes pnl for an equity trade" do
    expect(record.pnl).to eq(1000.0)  # (460 - 450) * 100
  end

  it "exposes gross and net pnl separately" do
    fee_record = described_class.new(
      id: "test-003",
      strategy_class: Class.new,
      symbol: "SPXW",
      direction: :credit,
      quantity: 1,
      entry_price: 2.10,
      exit_price: 1.20,
      entry_time: Time.parse("2024-01-15T09:30:00Z"),
      exit_time: Time.parse("2024-01-15T15:00:00Z"),
      legs: [{ symbol: "A" }, { symbol: "B" }, { symbol: "C" }, { symbol: "D" }],
      entry_fees: 2.28,
      entry_commissions: 2.60,
      exit_fees: 2.28,
      exit_commissions: 2.60
    )

    expect(fee_record.gross_pnl).to eq(90.0)
    expect(fee_record.total_transaction_costs).to eq(9.76)
    expect(fee_record.pnl).to eq(80.24)
  end

  it "identifies a winner" do
    expect(record.winner?).to be true
  end

  it "computes duration in minutes" do
    expect(record.duration_minutes).to eq(330)
  end

  context "with a losing trade" do
    let(:record) do
      described_class.new(
        id: "test-002", strategy_class: Class.new, symbol: "SPY",
        direction: :buy, quantity: 100,
        entry_price: 460.0, exit_price: 450.0,
        entry_time: Time.now, exit_time: Time.now + 60,
        legs: []
      )
    end

    it "identifies a loser" do
      expect(record.winner?).to be false
    end

    it "reports negative pnl" do
      expect(record.pnl).to eq(-1000.0)
    end
  end
end
