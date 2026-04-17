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

  it "applies execution costs to a filled iron condor" do
    broker = described_class.new(
      transaction_fee_model: QuantRb::Reality::PerSpreadTransactionFeeModel.new(
        option_fee_per_spread: 1.14,
        option_commission_per_spread: 1.30
      )
    )
    short_put = QuantRb::DataObjects::Option.new(
      symbol: "PUT_SHORT",
      underlying_symbol: "SPX",
      strike: 4900,
      put_call: QuantRb::PUT,
      underlying_price: 4950,
      expiration_date: Date.new(2024, 1, 19),
      bid: 1.60,
      ask: 1.70,
      mark: 1.65
    )
    long_put = QuantRb::DataObjects::Option.new(
      symbol: "PUT_LONG",
      underlying_symbol: "SPX",
      strike: 4850,
      put_call: QuantRb::PUT,
      underlying_price: 4950,
      expiration_date: Date.new(2024, 1, 19),
      bid: 0.45,
      ask: 0.55,
      mark: 0.50
    )
    short_call = QuantRb::DataObjects::Option.new(
      symbol: "CALL_SHORT",
      underlying_symbol: "SPX",
      strike: 5000,
      put_call: QuantRb::CALL,
      underlying_price: 4950,
      expiration_date: Date.new(2024, 1, 19),
      bid: 1.55,
      ask: 1.65,
      mark: 1.60
    )
    long_call = QuantRb::DataObjects::Option.new(
      symbol: "CALL_LONG",
      underlying_symbol: "SPX",
      strike: 5050,
      put_call: QuantRb::CALL,
      underlying_price: 4950,
      expiration_date: Date.new(2024, 1, 19),
      bid: 0.40,
      ask: 0.50,
      mark: 0.45
    )
    chain = QuantRb::DataObjects::OptionsChain.new(
      symbol: "SPXW",
      call_opts: [short_call, long_call],
      put_opts: [short_put, long_put]
    )
    slice = QuantRb::Engine::Slice.new(
      time: time,
      option_chains: { SPXW_options: { Date.new(2024, 1, 19) => chain } }
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
      limit_price: 2.0
    )

    broker.submit_order(order)
    broker.process_pending_orders(slice, portfolio)

    expect(portfolio.positions.fetch(order.id).entry_price).to eq(2.1)
    expect(portfolio.cash).to eq(5_205.12)
  end

  it "composes fill, slippage, and fee models via dependency injection" do
    fill_model = instance_double(QuantRb::Reality::FillModel, simulate_fill: 1.25)
    slippage_model = instance_double(QuantRb::Reality::SlippageModel, adjust_price: 1.15)
    fee_model = instance_double(
      QuantRb::Reality::TransactionFeeModel,
      estimate: QuantRb::Reality::CostBreakdown.new(fees: 1.0, commissions: 0.5)
    )
    broker = described_class.new(
      fill_model: fill_model,
      slippage_model: slippage_model,
      transaction_fee_model: fee_model
    )
    order = QuantRb::Engine::Order.new(
      legs: [{ symbol: :SPY, quantity: 1 }],
      quantity: 1,
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

    expect(fill_model).to have_received(:simulate_fill).with(order, slice)
    expect(slippage_model).to have_received(:adjust_price).with(1.25, order: order, slice: slice)
    expect(fee_model).to have_received(:estimate).with(order, fill_price: 1.15, slice: slice)
  end
end
