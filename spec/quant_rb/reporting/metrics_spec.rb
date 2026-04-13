# frozen_string_literal: true

require "spec_helper"

RSpec.describe QuantRb::Reporting::Metrics do
  def make_record(pnl_val)
    entry = 100.0
    exit  = entry + pnl_val   # pnl = (exit - entry) * qty(1) = pnl_val
    QuantRb::Reporting::TradeRecord.new(
      id:             SecureRandom.uuid,
      strategy_class: Class.new,
      symbol:         "SPY",
      direction:      :buy,
      quantity:       1,
      entry_price:    entry,
      exit_price:     exit,
      entry_time:     Time.now,
      exit_time:      Time.now + 60,
      legs:           []
    )
  end

  let(:trades) do
    [make_record(200), make_record(150), make_record(-100), make_record(-50)]
  end

  subject(:metrics) { described_class.new(trades) }

  it "counts total trades" do
    expect(metrics.total_trades).to eq(4)
  end

  it "computes win rate" do
    expect(metrics.win_rate).to eq(50.0)
  end

  it "computes total pnl" do
    expect(metrics.total_pnl).to be_within(0.01).of(200)
  end

  it "computes profit factor" do
    expect(metrics.profit_factor).to be > 1.0
  end

  it "computes max drawdown" do
    expect(metrics.max_drawdown).to be >= 0
  end

  it "returns a hash from to_h" do
    h = metrics.to_h
    expect(h).to include(:win_rate, :total_pnl, :profit_factor)
  end

  context "with no trades" do
    subject { described_class.new([]) }

    it "returns zero for all metrics" do
      expect(subject.win_rate).to eq(0.0)
      expect(subject.total_pnl).to eq(0.0)
    end
  end
end
