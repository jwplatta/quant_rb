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
end
