# frozen_string_literal: true

require "spec_helper"

RSpec.describe QuantRb::Data::DataSourcesRegistry do
  subject(:registry) { described_class.load(path: QUANT_RB_FIXTURES_ROOT.join("data_sources.yml")) }

  it "loads configured securities, indices, and option chains" do
    expect(registry.resolve_underlying(symbol: "SPY", resolution: :minute, kind: :security)).to include(
      symbol: "SPY",
      provider: "schwab",
      kind: :security
    )
    expect(registry.resolve_underlying(symbol: "SPX", resolution: :minute, kind: :index)).to include(
      symbol: "SPX",
      provider: "schwab",
      kind: :index
    )

    resolved = registry.resolve_option_chain(
      underlying: "SPX",
      option_root: "SPXW",
      resolution: :minute,
      dataset: "schwab_samples",
      chain_mode: nil,
      pricing_model: nil,
      iv_map: nil,
      validation: :repair,
      strike_grid: {},
      raw_options: {},
      market_timezone: "America/New_York"
    )

    expect(resolved.subscription).to include(
      option_root: "SPXW",
      provider: "schwab",
      underlying_provider: "schwab"
    )
    expect(resolved.config.chain_mode).to eq(:sampled_validated)
    expect(resolved.config.pricing_model).to eq(:black_scholes)
    expect(resolved.config.underlying_provider).to eq("schwab")
  end

  it "uses the synthetic default when no dataset is selected" do
    resolved = registry.resolve_option_chain(
      underlying: "SPX",
      option_root: "SPXW",
      resolution: :minute,
      dataset: nil,
      chain_mode: nil,
      pricing_model: :binomial,
      iv_map: nil,
      validation: :repair,
      strike_grid: {},
      raw_options: {},
      market_timezone: "America/New_York"
    )

    expect(resolved.subscription).to include(
      provider: "schwab",
      underlying_provider: "schwab"
    )
    expect(resolved.config.chain_mode).to eq(:synthetic)
    expect(resolved.config.pricing_model).to eq(:binomial)
    expect(resolved.config.iv_proxy).to eq("VIX")
  end

  it "raises when an option chain references the wrong underlying" do
    expect do
      registry.resolve_option_chain(
        underlying: "SPY",
        option_root: "SPXW",
        resolution: :minute,
        dataset: "schwab_samples",
        chain_mode: nil,
        pricing_model: nil,
        iv_map: nil,
        validation: :repair,
        strike_grid: {},
        raw_options: {},
        market_timezone: "America/New_York"
      )
    end.to raise_error(QuantRb::Error, /Configured underlying/)
  end

  it "raises when a named dataset does not exist" do
    expect do
      registry.resolve_option_chain(
        underlying: "SPX",
        option_root: "SPXW",
        resolution: :minute,
        dataset: "missing",
        chain_mode: nil,
        pricing_model: nil,
        iv_map: nil,
        validation: :repair,
        strike_grid: {},
        raw_options: {},
        market_timezone: "America/New_York"
      )
    end.to raise_error(QuantRb::Error, /No configured dataset/)
  end
end
