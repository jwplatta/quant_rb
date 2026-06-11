# frozen_string_literal: true

require "spec_helper"
require "csv"

RSpec.describe QuantRb::Data::Adapters::TickrakeAdapter do
  let(:loader) { instance_double(Tickrake::DataLoader) }
  let(:adapter) { described_class.new(loader: loader) }

  it "passes config_path to Tickrake::DataLoader when provided" do
    allow(Tickrake::DataLoader).to receive(:new).with(config_path: "/tmp/tickrake.yml").and_return(loader)

    described_class.new(config_path: "/tmp/tickrake.yml")

    expect(Tickrake::DataLoader).to have_received(:new).with(config_path: "/tmp/tickrake.yml")
  end

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

  it "delegates sampled option availability checks to Tickrake::DataLoader" do
    allow(loader).to receive(:options_available?).with(
      provider: "schwab",
      ticker: "SPX",
      option_root: "SPXW",
      start_date: Date.new(2026, 4, 10),
      end_date: Date.new(2026, 4, 10)
    ).and_return(true)

    available = adapter.option_data_available?(
      provider: "schwab",
      ticker: "SPX",
      option_root: "SPXW",
      start_date: Date.new(2026, 4, 10),
      end_date: Date.new(2026, 4, 10)
    )

    expect(available).to be(true)
  end

  it "delegates sampled option availability summaries to Tickrake::DataLoader" do
    summary = {
      available: true,
      sample_count: 4,
      earliest: Time.parse("2026-04-10 14:30:00 UTC"),
      latest: Time.parse("2026-04-10 20:55:00 UTC"),
      expirations: [Date.new(2026, 4, 10)]
    }
    allow(loader).to receive(:options_availability).with(
      provider: "schwab",
      ticker: "SPX",
      option_root: "SPXW",
      start_date: Date.new(2026, 4, 10),
      end_date: Date.new(2026, 4, 10)
    ).and_return(summary)

    availability = adapter.option_data_availability(
      provider: "schwab",
      ticker: "SPX",
      option_root: "SPXW",
      start_date: Date.new(2026, 4, 10),
      end_date: Date.new(2026, 4, 10)
    )

    expect(availability).to eq(summary)
  end

  it "selects bucketed snapshot refs for a slice without loading option rows" do
    raw_results = [
      Tickrake::Query::OptionsScanner::Result.new(
        provider_name: "schwab",
        ticker: "SPX",
        root_symbol: "SPXW",
        expiration_date: "2026-04-10",
        sample_datetime: "2026-04-10T14:31:00Z",
        file_path: "/tmp/early.csv"
      ),
      Tickrake::Query::OptionsScanner::Result.new(
        provider_name: "schwab",
        ticker: "SPX",
        root_symbol: "SPXW",
        expiration_date: "2026-04-10",
        sample_datetime: "2026-04-10T14:34:00Z",
        file_path: "/tmp/late.csv"
      )
    ]
    allow(loader).to receive(:send).with(
      :scan_options,
      provider: "schwab",
      ticker: "SPX",
      option_root: "SPXW",
      start_date: Date.new(2026, 4, 10),
      end_date: Date.new(2026, 4, 10)
    ).and_return(raw_results)
    allow(loader).to receive(:send).with(
      :select_option_results,
      raw_results,
      frequency: "5min",
      bucket_selector: :last
    ).and_return([raw_results.last])

    refs = adapter.option_snapshot_refs(
      provider: "schwab",
      ticker: "SPX",
      option_root: "SPXW",
      resolution: :"5min",
      start_date: Date.new(2026, 4, 10),
      end_date: Date.new(2026, 4, 10)
    )

    expect(refs.map(&:file_path)).to eq(["/tmp/late.csv"])
    expect(refs.map(&:sampled_at_utc)).to eq([Time.parse("2026-04-10T14:34:00Z")])
  end
end
