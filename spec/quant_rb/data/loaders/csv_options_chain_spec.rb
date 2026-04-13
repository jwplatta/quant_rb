# frozen_string_literal: true

require "spec_helper"

RSpec.describe QuantRb::Data::Loaders::CsvOptionsChain do
  let(:fixture_path) do
    File.expand_path("../../../fixtures/quant_rb/options/schwab/SPXW_exp2025-12-18_2025-12-18_13-50-58.csv", __dir__)
  end

  describe ".load" do
    it "parses a chain csv into options with greeks and metadata" do
      chain = described_class.load(fixture_path)

      expect(chain).to be_a(QuantRb::DataObjects::OptionsChain)
      expect(chain.symbol).to eq("SPXW")
      expect(chain.underlying_price).to eq(6005.0)
      expect(chain.call_opts.size).to eq(1)
      expect(chain.put_opts.size).to eq(1)

      call = chain.call_opts.first
      expect(call.symbol).to eq("SPXW  251218C06000000")
      expect(call.underlying_symbol).to eq("SPXW")
      expect(call.delta).to eq(0.44)
      expect(call.gamma).to eq(0.016)
      expect(call.theta).to eq(-0.85)
      expect(call.vega).to eq(1.31)
      expect(call.rho).to eq(0.09)
      expect(call.expiration_date).to eq(Date.new(2025, 12, 18))
      expect(call.days_to_expiration).to eq(0)
      expect(call.timestamp).to eq(Time.parse("2025-12-18 13:50:58"))
    end
  end
end
