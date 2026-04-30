# frozen_string_literal: true

require "spec_helper"

RSpec.describe QuantRb::Data::OptionChainSource do
  def candle(timestamp, close:, open: close, high: close + 1.0, low: close - 1.0, volume: 100)
    QuantRb::DataObjects::Candle.new(datetime: Time.parse(timestamp), open: open, high: high, low: low, close: close, volume: volume)
  end

  def series(*candles)
    QuantRb::Data::Series::CandleSeries.new(candles)
  end

  let(:adapter) do
    instance_double(QuantRb::Data::Adapters::TickrakeAdapter)
  end

  it "returns synthetic chains through the unified source contract" do
    config = QuantRb::Data::OptionChainConfig.new(
      underlying: "SPX",
      option_root: "SPXW",
      resolution: :minute,
      provider: "test",
      chain_mode: :synthetic,
      pricing_model: :black_scholes,
      iv_map: { "0DTE" => "VIX1D", "9DTE" => "VIX9D", "30DTE" => "VIX" },
      validation: :repair,
      strike_grid: { step: 10.0, range_ratio: 0.05 }
    )

    allow(adapter).to receive(:load_candle_series).with(provider: "test", ticker: "SPX", resolution: :minute, start_date: Date.new(2026, 4, 9), end_date: Date.new(2026, 4, 9)).and_return(
      series(
        candle("2026-04-08T20:00:00Z", close: 5050.0),
        candle("2026-04-09T15:00:00Z", close: 5100.0)
      )
    )
    allow(adapter).to receive(:load_candle_series).with(provider: "test", ticker: "VIX1D", resolution: :minute, start_date: Date.new(2026, 4, 9), end_date: Date.new(2026, 4, 9)).and_return(series(candle("2026-04-09T15:00:00Z", close: 15.0)))
    allow(adapter).to receive(:load_candle_series).with(provider: "test", ticker: "VIX9D", resolution: :minute, start_date: Date.new(2026, 4, 9), end_date: Date.new(2026, 4, 9)).and_return(series(candle("2026-04-09T15:00:00Z", close: 16.0)))
    allow(adapter).to receive(:load_candle_series).with(provider: "test", ticker: "VIX", resolution: :minute, start_date: Date.new(2026, 4, 9), end_date: Date.new(2026, 4, 9)).and_return(series(candle("2026-04-09T15:00:00Z", close: 18.0)))

    source = described_class.build(config:, start_date: Date.new(2026, 4, 9), end_date: Date.new(2026, 4, 9), adapter: adapter)
    chains = source.chains_at(Time.parse("2026-04-09T15:00:00Z"), expiry_filter: Date.new(2026, 4, 10))

    expect(chains.keys).to eq([Date.new(2026, 4, 10)])
    expect(chains.values.first.call_opts).not_to be_empty
    expect(chains.values.first.put_opts).not_to be_empty
  end

  it "reconstructs sampled interpolated chains and populates greeks" do
    config = QuantRb::Data::OptionChainConfig.new(
      underlying: "SPX",
      option_root: "SPXW",
      resolution: :minute,
      provider: "test",
      chain_mode: :sampled_interpolated,
      pricing_model: :black_scholes,
      iv_map: nil,
      validation: :repair,
      strike_grid: { step: 5.0 }
    )
    sampled_at = Time.parse("2026-04-09T15:00:00Z")
    expiry = Date.new(2026, 4, 10)
    rows = [
      { "symbol" => "C1", "contract_type" => "CALL", "strike" => 5100.0, "open" => 20.0, "high" => 22.0, "low" => 18.0, "close" => 21.0, "underlying_price" => 5105.0, "expiration_date" => expiry, "metadata" => { "sampled_at" => sampled_at, "expiration_date" => expiry } },
      { "symbol" => "C2", "contract_type" => "CALL", "strike" => 5110.0, "open" => 15.0, "high" => 16.0, "low" => 14.0, "close" => 15.5, "underlying_price" => 5105.0, "expiration_date" => expiry, "metadata" => { "sampled_at" => sampled_at, "expiration_date" => expiry } },
      { "symbol" => "P1", "contract_type" => "PUT", "strike" => 5100.0, "open" => 14.0, "high" => 15.0, "low" => 13.0, "close" => 14.5, "underlying_price" => 5105.0, "expiration_date" => expiry, "metadata" => { "sampled_at" => sampled_at, "expiration_date" => expiry } },
      { "symbol" => "P2", "contract_type" => "PUT", "strike" => 5110.0, "open" => 18.0, "high" => 20.0, "low" => 17.0, "close" => 19.0, "underlying_price" => 5105.0, "expiration_date" => expiry, "metadata" => { "sampled_at" => sampled_at, "expiration_date" => expiry } }
    ]
    allow(adapter).to receive(:load_option_chain_rows).and_return(rows)

    source = described_class.build(config:, start_date: Date.new(2026, 4, 9), end_date: Date.new(2026, 4, 9), adapter: adapter)
    chain = source.chains_at(sampled_at, expiry_filter: expiry).fetch(expiry)

    expect(chain.call_opts.map(&:strike)).to include(5105.0)
    expect(chain.all_options.all? { |opt| !opt.mark.nil? }).to be(true)
    expect(chain.all_options.any? { |opt| !opt.delta.nil? }).to be(true)
  end

  it "returns complete sampled chains without adding strikes in validated mode" do
    config = QuantRb::Data::OptionChainConfig.new(
      underlying: "SPX",
      option_root: "SPXW",
      resolution: :minute,
      provider: "test",
      chain_mode: :sampled_validated,
      pricing_model: :black_scholes,
      iv_map: nil,
      validation: :repair,
      strike_grid: { step: 5.0 }
    )
    sampled_at = Time.parse("2026-04-09T15:00:00Z")
    expiry = Date.new(2026, 4, 10)
    rows = [
      { "symbol" => "C1", "contract_type" => "CALL", "strike" => 5100.0, "mark" => 20.0, "bid" => 19.5, "ask" => 20.5, "underlying_price" => 5105.0, "expiration_date" => expiry, "delta" => 0.51, "metadata" => { "sampled_at" => sampled_at, "expiration_date" => expiry } },
      { "symbol" => "P1", "contract_type" => "PUT", "strike" => 5100.0, "mark" => 15.0, "bid" => 14.5, "ask" => 15.5, "underlying_price" => 5105.0, "expiration_date" => expiry, "delta" => -0.49, "metadata" => { "sampled_at" => sampled_at, "expiration_date" => expiry } }
    ]
    allow(adapter).to receive(:load_option_chain_rows).and_return(rows)

    source = described_class.build(config:, start_date: Date.new(2026, 4, 9), end_date: Date.new(2026, 4, 9), adapter: adapter)
    chain = source.chains_at(sampled_at, expiry_filter: expiry).fetch(expiry)

    expect(chain.call_opts.map(&:strike)).to eq([5100.0])
    expect(chain.put_opts.map(&:strike)).to eq([5100.0])
    expect(chain.call_opts.first.delta).to eq(0.51)
  end
end
