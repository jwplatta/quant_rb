# frozen_string_literal: true

require "spec_helper"

RSpec.describe QuantRb::Data::Index::OptionsChainIndex do
  let(:root_path) do
    File.expand_path("../../../fixtures/quant_rb/options/schwab", __dir__)
  end

  subject(:index) { described_class.new(root_path: root_path, symbol: "SPXW") }

  describe "#chains_at" do
    it "returns the latest chain set at or before the target time" do
      chains = index.chains_at(Time.parse("2025-12-18 13:52:00"))

      expect(chains.keys).to eq([Date.new(2025, 12, 18), Date.new(2025, 12, 19)])
      expect(chains.fetch(Date.new(2025, 12, 18)).underlying_price).to eq(6005.0)
      expect(chains.fetch(Date.new(2025, 12, 19)).call_opts.first.delta).to eq(0.39)
    end

    it "uses locf when only an earlier sample exists" do
      chains = index.chains_at(Time.parse("2025-12-18 13:46:00"))

      expect(chains.keys).to eq([Date.new(2025, 12, 18)])
      expect(chains.fetch(Date.new(2025, 12, 18)).underlying_price).to eq(5988.0)
    end

    it "supports expiry filtering" do
      chains = index.chains_at(
        Time.parse("2025-12-18 13:52:00"),
        expiry_filter: ->(expiry) { expiry == Date.new(2025, 12, 19) }
      )

      expect(chains.keys).to eq([Date.new(2025, 12, 19)])
    end
  end

  describe "#available_dates" do
    it "returns distinct sample dates" do
      expect(index.available_dates).to eq([Date.new(2025, 12, 18)])
    end
  end
end
