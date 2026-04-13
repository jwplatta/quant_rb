# frozen_string_literal: true

require "spec_helper"

RSpec.describe QuantRb::DataObjects::Candle do
  let(:candle) do
    described_class.new(
      datetime: Time.parse("2024-01-15T14:30:00Z"),
      open:  500.0,
      high:  505.0,
      low:   498.0,
      close: 502.5,
      volume: 1000
    )
  end

  it "stores all OHLCV fields" do
    expect(candle.open).to eq(500.0)
    expect(candle.high).to eq(505.0)
    expect(candle.low).to eq(498.0)
    expect(candle.close).to eq(502.5)
    expect(candle.volume).to eq(1000)
  end

  it "stores the datetime" do
    expect(candle.datetime).to be_a(Time)
  end

  it "serializes to hash" do
    h = candle.to_h
    expect(h[:close]).to eq(502.5)
    expect(h[:datetime]).to eq(candle.datetime)
  end
end
