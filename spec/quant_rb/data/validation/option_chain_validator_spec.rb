# frozen_string_literal: true

require "spec_helper"

RSpec.describe QuantRb::Data::Validation::OptionChainValidator do
  def option(symbol:, strike:, put_call:, mark:, underlying_price: 100.0)
    QuantRb::DataObjects::Option.new(
      symbol: symbol,
      underlying_symbol: "SPX",
      strike: strike,
      put_call: put_call,
      underlying_price: underlying_price,
      expiration_date: Date.new(2026, 4, 10),
      days_to_expiration: 5,
      mark: mark,
      bid: mark,
      ask: mark
    )
  end

  it "repairs monotonicity and intrinsic floor violations" do
    chain = QuantRb::DataObjects::OptionsChain.new(
      symbol: "SPXW",
      underlying_price: 100.0,
      call_opts: [
        option(symbol: "C1", strike: 95.0, put_call: QuantRb::CALL, mark: 2.0),
        option(symbol: "C2", strike: 100.0, put_call: QuantRb::CALL, mark: 4.0)
      ],
      put_opts: [
        option(symbol: "P1", strike: 95.0, put_call: QuantRb::PUT, mark: 2.0),
        option(symbol: "P2", strike: 100.0, put_call: QuantRb::PUT, mark: 1.0)
      ]
    )

    repaired = described_class.new.repair(chain)
    violations = described_class.new.validate(repaired)

    expect(violations).to be_empty
    expect(repaired.call_opts.first.mark).to be >= 5.0
    expect(repaired.call_opts.first.mark).to be >= repaired.call_opts.last.mark
    expect(repaired.put_opts.first.mark).to be <= repaired.put_opts.last.mark
  end
end
