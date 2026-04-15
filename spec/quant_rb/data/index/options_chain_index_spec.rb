# frozen_string_literal: true

require "spec_helper"
require "time"

RSpec.describe QuantRb::Data::Index::OptionsChainIndex do
  let(:root_path) do
    QUANT_RB_FIXTURES_ROOT.join("options", "schwab")
  end

  subject(:index) { described_class.new(root_path: root_path, symbol: "SPXW") }

  describe "#chains_at" do
    it "returns the latest available sample for each expiry at or before the target time" do
      chains = index.chains_at(Time.parse("2025-12-18 13:52:00"))

      expect(chains.keys).to eq([Date.new(2025, 12, 18), Date.new(2025, 12, 19)])
      expect(chains.fetch(Date.new(2025, 12, 18)).underlying_price).to eq(6005.0)
      expect(chains.fetch(Date.new(2025, 12, 19)).call_opts.first.delta).to eq(0.39)
    end

    it "uses locf independently per expiry when only an earlier sample exists" do
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

    it "returns all available expiries even when their latest samples have different timestamps" do
      mixed_root = QUANT_RB_FIXTURES_ROOT.join("options", "per_expiry_locf")
      mixed_index = described_class.new(root_path: mixed_root, symbol: "SPXW")

      chains = mixed_index.chains_at(Time.parse("2026-04-13 14:50:00"))

      expect(chains.keys).to eq([Date.new(2026, 4, 14), Date.new(2026, 4, 15)])
      expect(chains.fetch(Date.new(2026, 4, 14)).underlying_price).to eq(6820.16)
      expect(chains.fetch(Date.new(2026, 4, 15)).underlying_price).to eq(6821.87)
    end

    it "excludes expiries that are already past the target date" do
      chains = index.chains_at(Time.parse("2026-01-05 20:50:00 UTC"))

      expect(chains).to eq({})
    end
  end

  describe "#available_dates" do
    it "returns distinct sample dates" do
      expect(index.available_dates).to eq([Date.new(2025, 12, 18)])
    end
  end

  describe "initialization" do
    it "raises when the configured root path is missing" do
      expect do
        described_class.new(root_path: "/tmp/definitely-missing-options-root", symbol: "SPXW")
      end.to raise_error(ArgumentError, /Options chain root path not found/)
    end
  end
end
