# frozen_string_literal: true

require "spec_helper"

RSpec.describe QuantRb::Engine::FillModel do
  let(:fill_model) { described_class.new(model: :bid_ask) }
  let(:time) { Time.parse("2024-01-15 15:00:00 UTC") }

  it "fills market orders from the current candle close" do
    order = QuantRb::Engine::Order.new(
      legs: [{ symbol: :SPY, quantity: 10 }],
      quantity: 10,
      direction: :buy
    )
    candle = QuantRb::DataObjects::Candle.new(
      datetime: time,
      open: 500.0,
      high: 501.0,
      low: 499.0,
      close: 500.5,
      volume: 1_000
    )
    slice = QuantRb::Engine::Slice.new(time: time, bars: { SPY: candle })

    expect(fill_model.simulate_fill(order, slice)).to eq(500.5)
  end

  it "applies adverse slippage to equity buys and sells" do
    slippage_model = described_class.new(model: :bid_ask, slippage: 0.15)
    buy_order = QuantRb::Engine::Order.new(
      legs: [{ symbol: :SPY, quantity: 1 }],
      quantity: 1,
      direction: :buy
    )
    sell_order = QuantRb::Engine::Order.new(
      legs: [{ symbol: :SPY, quantity: -1 }],
      quantity: 1,
      direction: :sell
    )
    candle = QuantRb::DataObjects::Candle.new(
      datetime: time,
      open: 500.0,
      high: 501.0,
      low: 499.0,
      close: 500.5,
      volume: 1_000
    )
    slice = QuantRb::Engine::Slice.new(time: time, bars: { SPY: candle })

    expect(slippage_model.simulate_fill(buy_order, slice)).to eq(500.65)
    expect(slippage_model.simulate_fill(sell_order, slice)).to eq(500.35)
  end

  it "returns a positive net credit for a short spread" do
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
      bid: 0.95,
      ask: 1.05,
      mark: 1.00
    )
    chain = QuantRb::DataObjects::OptionsChain.new(symbol: "SPXW", call_opts: [short_call, long_call])
    order = QuantRb::Engine::Order.new(
      legs: [{ symbol: "SHORT", quantity: -1 }, { symbol: "LONG", quantity: 1 }],
      quantity: 1,
      direction: :credit,
      limit_price: 1.0
    )
    slice = QuantRb::Engine::Slice.new(
      time: time,
      option_chains: { SPXW_options: { Date.new(2024, 1, 19) => chain } }
    )

    expect(fill_model.simulate_fill(order, slice)).to eq(1.05)
  end

  it "applies adverse slippage to credit and debit combo fills" do
    slippage_model = described_class.new(model: :bid_ask, slippage: 0.05)
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
      bid: 0.95,
      ask: 1.05,
      mark: 1.00
    )
    chain = QuantRb::DataObjects::OptionsChain.new(symbol: "SPXW", call_opts: [short_call, long_call])
    credit_order = QuantRb::Engine::Order.new(
      legs: [{ symbol: "SHORT", quantity: -1 }, { symbol: "LONG", quantity: 1 }],
      quantity: 1,
      direction: :credit,
      limit_price: 1.0
    )
    debit_order = QuantRb::Engine::Order.new(
      legs: [{ symbol: "LONG", quantity: 1 }, { symbol: "SHORT", quantity: -1 }],
      quantity: 1,
      direction: :debit,
      limit_price: 1.0
    )
    slice = QuantRb::Engine::Slice.new(
      time: time,
      option_chains: { SPXW_options: { Date.new(2024, 1, 19) => chain } }
    )

    expect(slippage_model.simulate_fill(credit_order, slice)).to eq(1.0)
    expect(slippage_model.simulate_fill(debit_order, slice)).to eq(1.1)
  end
end
