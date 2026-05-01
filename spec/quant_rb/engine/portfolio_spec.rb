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

  it "tracks gross pnl and transaction costs for a one-lot iron condor" do
    fee_model = QuantRb::Reality::PerSpreadTransactionFeeModel.new(
      option_fee_per_spread: 1.14,
      option_commission_per_spread: 1.30
    )
    order = QuantRb::Engine::Order.new(
      legs: [
        { symbol: "PUT_SHORT", quantity: -1 },
        { symbol: "PUT_LONG", quantity: 1 },
        { symbol: "CALL_SHORT", quantity: -1 },
        { symbol: "CALL_LONG", quantity: 1 }
      ],
      quantity: 1,
      direction: :credit,
      limit_price: 2.10,
      submitted_at: time
    )

    portfolio.record_fill(order, 2.10, time, transaction_costs: fee_model.estimate(order))
    portfolio.close_position(order.id, 1.20, time + 3600, transaction_costs: fee_model.estimate(order))

    trade = portfolio.trade_history.last
    expect(trade.gross_pnl).to eq(90.0)
    expect(trade.total_fees).to eq(4.56)
    expect(trade.total_commissions).to eq(5.2)
    expect(trade.total_transaction_costs).to eq(9.76)
    expect(trade.pnl).to eq(80.24)
    expect(portfolio.cash).to eq(10_080.24)
  end

  it "automatically settles expired option spreads when leg metadata is present" do
    order = QuantRb::Engine::Order.new(
      legs: [
        { symbol: "SPXW_2024-01-19_P_4900", quantity: -1, expiration_date: Date.new(2024, 1, 19), strike: 4900.0, put_call: QuantRb::PUT, underlying_symbol: "SPX" },
        { symbol: "SPXW_2024-01-19_P_4880", quantity: 1, expiration_date: Date.new(2024, 1, 19), strike: 4880.0, put_call: QuantRb::PUT, underlying_symbol: "SPX" }
      ],
      quantity: 1,
      direction: :credit,
      limit_price: 1.10,
      submitted_at: time
    )
    portfolio.record_fill(order, 1.10, time)

    expiry_time = Time.parse("2024-01-20 00:00:00 UTC")
    slice = QuantRb::Engine::Slice.new(
      time: expiry_time,
      bars: {
        SPX: QuantRb::DataObjects::Candle.new(
          datetime: expiry_time,
          open: 4890.0,
          high: 4895.0,
          low: 4875.0,
          close: 4875.0,
          volume: 0
        )
      }
    )

    portfolio.process_expirations(slice)

    expect(portfolio.positions).to be_empty
    expect(portfolio.trade_history.size).to eq(1)
    expect(portfolio.trade_history.last.exit_price).to eq(20.0)
    expect(portfolio.cash).to eq(8_110.0)
  end
end
