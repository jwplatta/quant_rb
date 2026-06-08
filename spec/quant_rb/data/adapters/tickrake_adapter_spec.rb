# frozen_string_literal: true

require "spec_helper"

RSpec.describe QuantRb::Data::Adapters::TickrakeAdapter do
  let(:loader) { instance_double(Tickrake::DataLoader) }
  let(:adapter) { described_class.new(loader: loader) }

  it "passes timezone through when loading candle series and uses datetime_tz as runtime time" do
    row = {
      "datetime_utc" => Time.parse("2026-04-10 14:30:00 UTC"),
      "datetime_tz" => Time.parse("2026-04-10 09:30:00 -0500"),
      "open" => 5100.0,
      "high" => 5101.0,
      "low" => 5099.0,
      "close" => 5100.5,
      "volume" => 12
    }
    allow(loader).to receive(:load_candles).with(
      provider: "ibkr-paper",
      ticker: "SPX",
      frequency: "1min",
      start_date: Date.new(2026, 4, 10),
      end_date: Date.new(2026, 4, 10),
      timezone: "America/Chicago"
    ).and_return([row])

    series = adapter.load_candle_series(
      provider: "ibkr-paper",
      ticker: "SPX",
      resolution: :minute,
      start_date: Date.new(2026, 4, 10),
      end_date: Date.new(2026, 4, 10),
      timezone: "America/Chicago"
    )

    expect(series.to_a.first.datetime).to eq(row.fetch("datetime_tz"))
  end

  it "passes timezone through when loading option chain rows" do
    allow(loader).to receive(:load_option_chains).with(
      provider: "schwab",
      ticker: "SPX",
      option_root: "SPXW",
      start_date: Date.new(2026, 4, 10),
      end_date: Date.new(2026, 4, 10),
      frequency: "5min",
      timezone: "America/Chicago",
      include_metadata: true,
      order: :sample_time_asc
    ).and_return([])

    adapter.load_option_chain_rows(
      provider: "schwab",
      ticker: "SPX",
      option_root: "SPXW",
      resolution: :"5min",
      start_date: Date.new(2026, 4, 10),
      end_date: Date.new(2026, 4, 10),
      timezone: "America/Chicago"
    )

    expect(loader).to have_received(:load_option_chains)
  end
end
