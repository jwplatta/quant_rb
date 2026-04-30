# frozen_string_literal: true

require "spec_helper"

RSpec.describe "QuantRb pricing" do
  it "prices a call with Black-Scholes and computes a plausible delta" do
    price = QuantRb::Data::Pricing::BlackScholes.price(
      spot: 100.0,
      strike: 100.0,
      tau_years: 30.0 / 365.25,
      sigma: 0.20,
      rate: 0.01,
      contract_type: QuantRb::CALL
    )
    delta = QuantRb::Data::Pricing::BlackScholes.delta(
      spot: 100.0,
      strike: 100.0,
      tau_years: 30.0 / 365.25,
      sigma: 0.20,
      rate: 0.01,
      contract_type: QuantRb::CALL
    )

    expect(price).to be > 0.0
    expect(delta).to be_between(0.45, 0.60)
  end

  it "keeps CRR price close to Black-Scholes for a European-style case" do
    black_scholes = QuantRb::Data::Pricing::BlackScholes.price(
      spot: 100.0,
      strike: 100.0,
      tau_years: 30.0 / 365.25,
      sigma: 0.20,
      rate: 0.01,
      contract_type: QuantRb::CALL
    )
    binomial = QuantRb::Data::Pricing::CrrBinomial.price(
      spot: 100.0,
      strike: 100.0,
      tau_years: 30.0 / 365.25,
      sigma: 0.20,
      rate: 0.01,
      contract_type: QuantRb::CALL
    )

    expect((binomial - black_scholes).abs).to be < 0.25
  end

  it "backs out implied volatility from a market price" do
    market_price = QuantRb::Data::Pricing::BlackScholes.price(
      spot: 100.0,
      strike: 100.0,
      tau_years: 30.0 / 365.25,
      sigma: 0.25,
      rate: 0.01,
      contract_type: QuantRb::CALL
    )

    sigma = QuantRb::Data::Pricing::ImpliedVolatilitySolver.solve(
      market_price: market_price,
      spot: 100.0,
      strike: 100.0,
      tau_years: 30.0 / 365.25,
      rate: 0.01,
      contract_type: QuantRb::CALL
    )

    expect(sigma).to be_within(0.01).of(0.25)
  end
end
