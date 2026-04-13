# frozen_string_literal: true

require "spec_helper"

RSpec.describe QuantRb::Brokers::BacktestBroker do
  let(:time) { Time.parse("2024-01-15 15:00:00 UTC") }
  let(:portfolio) { QuantRb::Engine::Portfolio.new(initial_cash: 5_000) }
  let(:broker) { described_class.new }

  it "fills market orders and removes them from the pending queue" do
    order = QuantRb::Engine::Order.new(
      legs: [{ symbol: :SPY, quantity: 5 }],
      quantity: 5,
      direction: :buy
    )
    candle = QuantRb::DataObjects::Candle.new(
      datetime: time,
      open: 100.0,
      high: 101.0,
      low: 99.0,
      close: 100.5,
      volume: 100
    )
    slice = QuantRb::Engine::Slice.new(time: time, bars: { SPY: candle })

    broker.submit_order(order)
    broker.process_pending_orders(slice, portfolio)

    expect(broker.pending_orders).to be_empty
    expect(portfolio.positions[:SPY].quantity).to eq(5)
    expect(portfolio.cash).to eq(4_497.5)
  end

  it "respects combo credit order limits" do
    short_call = QuantRb::DataObjects::Option.new(
      symbol: "SHORT",
      underlying_symbol: "SPX",
      strike: 5000,
      put_call: QuantRb::CALL,
      underlying_price: 4950,
      expiration_date: Date.new(2024, 1, 19),
      bid: 2.10,
      ask: 2.30,
      mark: 2.20
    )
    long_call = QuantRb::DataObjects::Option.new(
      symbol: "LONG",
      underlying_symbol: "SPX",
      strike: 5050,
      put_call: QuantRb::CALL,
      underlying_price: 4950,
      expiration_date: Date.new(2024, 1, 19),
      bid: 1.15,
      ask: 1.25,
      mark: 1.20
    )
    chain = QuantRb::DataObjects::OptionsChain.new(symbol: "SPXW", call_opts: [short_call, long_call])
    slice = QuantRb::Engine::Slice.new(
      time: time,
      option_chains: { SPXW_options: { Date.new(2024, 1, 19) => chain } }
    )
    order = QuantRb::Engine::Order.new(
      legs: [{ symbol: "SHORT", quantity: -1 }, { symbol: "LONG", quantity: 1 }],
      quantity: 1,
      direction: :credit,
      limit_price: 1.00
    )

    broker.submit_order(order)
    broker.process_pending_orders(slice, portfolio)

    expect(portfolio.positions[order.id]).to be_nil
    expect(broker.pending_orders.map(&:id)).to include(order.id)
  end
end
