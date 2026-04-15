# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe QuantRb::Data::Loaders::CsvCandle do
  around do |example|
    original_logger = QuantRb.logger
    begin
      example.run
    ensure
      QuantRb.logger = original_logger
    end
  end

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

    it "logs malformed rows through QuantRb.logger" do
      fixture = Tempfile.new(["bad_candles", ".csv"])
      fixture.write("datetime,open,high,low,close,volume\n")
      fixture.write("bad,1,2,3,4,5\n")
      fixture.close

      logger = instance_double(Logger, warn: nil)
      QuantRb.logger = logger

      expect(logger).to receive(:warn).with(include("Skipping malformed candle row"))
      expect(described_class.load(fixture.path)).to eq([])
    ensure
      fixture.close!
    end
  end
end
