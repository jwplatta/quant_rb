# frozen_string_literal: true

require "spec_helper"

RSpec.describe QuantRb::DataObjects::Option do
  let(:call_option) do
    described_class.new(
      symbol:           "SPXW  260202C05800000",
      underlying_symbol: "SPXW",
      strike:           5800.0,
      put_call:         QuantRb::CALL,
      underlying_price: 5750.0,
      expiration_date:  Date.new(2026, 2, 2),
      mark:             12.5,
      bid:              12.0,
      ask:              13.0,
      delta:            0.08,
      gamma:            0.002,
      theta:           -0.5,
      vega:             1.2,
      rho:              0.1
    )
  end

  let(:put_option) do
    described_class.new(
      symbol:           "SPXW  260202P05500000",
      underlying_symbol: "SPXW",
      strike:           5500.0,
      put_call:         QuantRb::PUT,
      underlying_price: 5750.0,
      expiration_date:  Date.new(2026, 2, 2),
      mark:             10.0,
      bid:              9.5,
      ask:              10.5,
      delta:           -0.06
    )
  end

  describe "#call? / #put?" do
    it "identifies calls" do
      expect(call_option.call?).to be true
      expect(call_option.put?).to be false
    end

    it "identifies puts" do
      expect(put_option.put?).to be true
      expect(put_option.call?).to be false
    end
  end

  describe "#in_the_money?" do
    it "returns false for OTM call" do
      expect(call_option.in_the_money?).to be false
    end

    it "returns false for OTM put" do
      expect(put_option.in_the_money?).to be false
    end
  end

  describe "#mid" do
    it "returns midpoint of bid and ask" do
      expect(call_option.mid).to eq(12.5)
    end
  end

  describe "#to_h / .from_h" do
    it "round-trips through to_h and from_h" do
      h = call_option.to_h
      rebuilt = described_class.from_h(h)
      expect(rebuilt.symbol).to eq(call_option.symbol)
      expect(rebuilt.delta).to eq(call_option.delta)
    end
  end
end
