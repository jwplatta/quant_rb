# frozen_string_literal: true

require "spec_helper"
require "time"

RSpec.describe QuantRb::Data::Index::SyntheticOptionsChainIndex do
  def candle(timestamp, close:, open: close, high: close + 1.0, low: close - 1.0, volume: 1_000)
    QuantRb::DataObjects::Candle.new(
      datetime: Time.parse(timestamp),
      open: open,
      high: high,
      low: low,
      close: close,
      volume: volume
    )
  end

  def series(*candles)
    QuantRb::Data::Series::CandleSeries.new(candles)
  end

  let(:builder) do
    QuantRb::Data::Synthetic::SyntheticChainBuilder.new(
      underlying_series: series(
        candle("2025-12-17T20:00:00Z", close: 5_130.0, open: 5_120.0),
        candle("2025-12-18T14:30:00Z", close: 5_145.0, open: 5_140.0),
        candle("2025-12-18T15:00:00Z", close: 5_150.0, open: 5_145.0)
      ),
      iv_proxy_series: series(
        candle("2025-12-17T20:00:00Z", close: 18.0),
        candle("2025-12-18T15:00:00Z", close: 17.5)
      ),
      underlying_symbol: "SPX",
      iv_proxy_symbol: "VIX"
    )
  end

  subject(:index) { described_class.new(symbol: "SPXW", synthetic_builder: builder) }

  describe "#chains_at" do
    it "builds a synthetic chain for an explicit expiry" do
      expiry = Date.new(2025, 12, 24)
      chains = index.chains_at(Time.parse("2025-12-18 15:00:00 UTC"), expiry_filter: expiry)

      expect(chains.keys).to eq([expiry])
      expect(chains.fetch(expiry).underlying_price).to eq(5_150.0)
      expect(chains.fetch(expiry).call_opts).not_to be_empty
      expect(chains.fetch(expiry).put_opts).not_to be_empty
    end

    it "returns no chain until the synthetic builder has enough input data" do
      incomplete_builder = instance_double(QuantRb::Data::Synthetic::SyntheticChainBuilder)
      allow(incomplete_builder).to receive(:build).and_raise(
        ArgumentError, "SyntheticChainBuilder requires VIX candle data"
      )

      index = described_class.new(symbol: "SPXW", synthetic_builder: incomplete_builder)
      chains = index.chains_at(Time.parse("2025-12-18 13:30:00 UTC"), expiry_filter: Date.new(2025, 12, 24))

      expect(chains).to eq({})
    end
  end
end
