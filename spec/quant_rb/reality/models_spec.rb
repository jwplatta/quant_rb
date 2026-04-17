# frozen_string_literal: true

require "spec_helper"

RSpec.describe "reality models" do
  it "computes per-spread fees and commissions" do
    model = QuantRb::Reality::PerSpreadTransactionFeeModel.new(
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
      limit_price: 2.10
    )

    costs = model.estimate(order)
    expect(costs.fees).to eq(2.28)
    expect(costs.commissions).to eq(2.6)
    expect(costs.total).to eq(4.88)
  end

  it "requires custom models to implement their interface" do
    expect do
      QuantRb::Reality::FillModel.new.simulate_fill(nil, nil)
    end.to raise_error(NotImplementedError)

    expect do
      QuantRb::Reality::SlippageModel.new.adjust_price(1.0, order: nil)
    end.to raise_error(NotImplementedError)

    expect do
      QuantRb::Reality::TransactionFeeModel.new.estimate(nil)
    end.to raise_error(NotImplementedError)
  end
end
