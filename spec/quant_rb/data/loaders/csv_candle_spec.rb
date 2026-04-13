# frozen_string_literal: true

require "spec_helper"

RSpec.describe QuantRb::Data::Loaders::CsvCandle do
  let(:fixture_path) do
    QUANT_RB_FIXTURES_ROOT.join("history", "schwab", "SPY", "SPY_1min.csv")
  end

  describe ".load" do
    it "parses rows into candle objects" do
      candles = described_class.load(fixture_path)

      expect(candles.size).to eq(3)
      expect(candles.first).to be_a(QuantRb::DataObjects::Candle)
      expect(candles.first.datetime).to eq(Time.iso8601("2024-01-02T14:30:00Z"))
      expect(candles.first.open).to eq(100.0)
      expect(candles.first.close).to eq(100.5)
      expect(candles.first.volume).to eq(1000)
    end
  end
end
