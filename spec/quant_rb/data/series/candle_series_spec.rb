# frozen_string_literal: true

require "spec_helper"

RSpec.describe QuantRb::Data::Series::CandleSeries do
  let(:data_path) do
    QUANT_RB_FIXTURES_ROOT.join("history", "schwab")
  end

  let(:series) do
    QuantRb::Data::Series::CandleLoader.load(symbol: "SPY", resolution: :minute, data_path: data_path)
  end

  describe QuantRb::Data::Series::CandleLoader do
    it "loads a candle series from csv" do
      expect(series).to be_a(QuantRb::Data::Series::CandleSeries)
      expect(series.size).to eq(3)
    end
  end

  describe "#at" do
    it "returns the last candle at or before the target time" do
      candle = series.at(Time.iso8601("2024-01-02T14:31:30Z"))

      expect(candle.datetime).to eq(Time.iso8601("2024-01-02T14:31:00Z"))
      expect(candle.close).to eq(101.5)
    end

    it "returns nil when no candle exists at or before the target time" do
      expect(series.at(Time.iso8601("2024-01-02T14:29:00Z"))).to be_nil
    end
  end

  describe "#slice" do
    it "returns candles in the requested time range" do
      candles = series.slice(Time.iso8601("2024-01-02T14:30:30Z"), Time.iso8601("2024-01-02T14:32:00Z"))

      expect(candles.map(&:datetime)).to eq(
        [
          Time.iso8601("2024-01-02T14:31:00Z"),
          Time.iso8601("2024-01-02T14:32:00Z")
        ]
      )
    end
  end

  describe "#last" do
    it "returns the last n candles" do
      expect(series.last(2).map(&:close)).to eq([101.5, 102.75])
    end
  end
end
