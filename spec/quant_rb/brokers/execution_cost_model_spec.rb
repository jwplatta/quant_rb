# frozen_string_literal: true

require "spec_helper"

RSpec.describe QuantRb::Brokers::ExecutionCostModel do
  it "computes Schwab-style fees and commissions for a one-lot iron condor" do
    model = described_class.schwab_spxw_options
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
end
