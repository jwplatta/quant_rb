# frozen_string_literal: true

require "spec_helper"

RSpec.describe QuantRb::Engine::Portfolio do
  let(:time) { Time.parse("2024-01-15 15:00:00 UTC") }
  let(:portfolio) { described_class.new(initial_cash: 10_000) }

  it "tracks long equity entries and exits into trade history" do
    buy_order = QuantRb::Engine::Order.new(
      legs: [{ symbol: :SPY, quantity: 10 }],
      quantity: 10,
      direction: :buy,
      submitted_at: time
    )
    sell_order = QuantRb::Engine::Order.new(
      legs: [{ symbol: :SPY, quantity: -10 }],
      quantity: 10,
      direction: :sell,
      submitted_at: time + 3600
    )

    portfolio.record_fill(buy_order, 500.0, time)
    portfolio.record_fill(sell_order, 510.0, time + 3600)

    expect(portfolio.positions).to be_empty
    expect(portfolio.trade_history.size).to eq(1)
    expect(portfolio.trade_history.first.pnl).to eq(100.0)
    expect(portfolio.cash).to eq(10_100.0)
  end

  it "books premium for credit spreads and logs the trade on close" do
    order = QuantRb::Engine::Order.new(
      legs: [{ symbol: "SHORT", quantity: -1 }, { symbol: "LONG", quantity: 1 }],
      quantity: 1,
      direction: :credit,
      limit_price: 1.10,
      submitted_at: time
    )

    portfolio.record_fill(order, 1.10, time)
    portfolio.close_position(order.id, 0.40, time + 3600)

    expect(portfolio.cash).to eq(10_070.0)
    expect(portfolio.trade_history.last.pnl).to eq(70.0)
  end
end
