# frozen_string_literal: true

require "spec_helper"

RSpec.describe QuantRb::Data::OptionChainConfig do
  it "normalizes pricing model and iv buckets" do
    config = described_class.new(
      underlying: "SPX",
      option_root: "SPXW",
      resolution: :minute,
      provider: "test",
      chain_mode: :synthetic,
      pricing_model: :crr,
      iv_map: { "0DTE" => "VIX1D", "9DTE" => "VIX9D", "30DTE" => "VIX" },
      validation: :repair,
      strike_grid: { step: 10.0 }
    )

    expect(config.pricing_model).to eq(:binomial)
    expect(config.iv_proxy_for_dte(0)).to eq("VIX1D")
    expect(config.iv_proxy_for_dte(5)).to eq("VIX9D")
    expect(config.iv_proxy_for_dte(20)).to eq("VIX")
  end

  it "rejects unsupported synthetic config without iv map" do
    expect do
      described_class.new(
        underlying: "SPX",
        option_root: "SPXW",
        resolution: :minute,
        provider: "test",
        chain_mode: :synthetic,
        pricing_model: :black_scholes,
        iv_map: nil,
        validation: :repair,
        strike_grid: {}
      )
    end.to raise_error(ArgumentError, /IV mapping/)
  end
end
