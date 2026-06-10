# frozen_string_literal: true

require "csv"
require "spec_helper"

RSpec.describe QuantRb::Data::OptionChainSource do
  def parse_filename_timestamp_utc(sample_date, sample_time)
    Time.strptime("#{sample_date} #{sample_time.tr('-', ':')} UTC", "%Y-%m-%d %H:%M:%S %Z").utc
  end

  def candle(timestamp, close:, open: close, high: close + 1.0, low: close - 1.0, volume: 100)
    QuantRb::DataObjects::Candle.new(datetime: Time.parse(timestamp), open: open, high: high, low: low, close: close, volume: volume)
  end

  def series(*candles)
    QuantRb::Data::Series::CandleSeries.new(candles)
  end

  def fixture_option_rows(filename)
    path = QUANT_RB_FIXTURES_ROOT.join("options", "schwab", filename)
    match = File.basename(path).match(/\ASPXW_exp(?<expiry>\d{4}-\d{2}-\d{2})_(?<sample_date>\d{4}-\d{2}-\d{2})_(?<sample_time>\d{2}-\d{2}-\d{2})\.csv\z/)
    raise "Unexpected fixture filename: #{filename}" unless match

    sampled_at_utc = parse_filename_timestamp_utc(match[:sample_date], match[:sample_time])
    sampled_at_tz = sampled_at_utc.getlocal("-05:00")
    expiry = Date.parse(match[:expiry])

    CSV.foreach(path, headers: true).map do |row|
      row.to_h.merge(
        "sampled_at_utc" => sampled_at_utc,
        "sampled_at_tz" => sampled_at_tz,
        "strike" => row["strike"].to_f,
        "expiration_date" => expiry,
        "mark" => row["mark"].to_f,
        "bid" => row["bid"].to_f,
        "ask" => row["ask"].to_f,
        "underlying_price" => row["underlying_price"].to_f,
        "delta" => row["delta"].to_f,
        "gamma" => row["gamma"].to_f,
        "theta" => row["theta"].to_f,
        "vega" => row["vega"].to_f,
        "rho" => row["rho"].to_f,
        "volatility" => row["volatility"].to_f,
        "open_interest" => row["open_interest"].to_i,
        "total_volume" => row["total_volume"].to_i,
        "intrinsic_value" => row["intrinsic_value"].to_f,
        "extrinsic_value" => row["extrinsic_value"].to_f,
        "metadata" => {
          "sampled_at_utc" => sampled_at_utc,
          "sampled_at_tz" => sampled_at_tz,
          "expiration_date" => expiry
        }
      )
    end
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
      iv_map: "VIX",
      validation: :repair,
      strike_grid: { step: 10.0, range_ratio: 0.05 }
    )

    allow(adapter).to receive(:load_candle_series).with(provider: "test", ticker: "SPX", resolution: :minute, start_date: Date.new(2026, 4, 9), end_date: Date.new(2026, 4, 9), timezone: "America/New_York").and_return(
      series(
        candle("2026-04-08T20:00:00Z", close: 5050.0),
        candle("2026-04-09T15:00:00Z", close: 5100.0)
      )
    )
    allow(adapter).to receive(:load_candle_series).with(provider: "test", ticker: "VIX", resolution: :minute, start_date: Date.new(2026, 4, 9), end_date: Date.new(2026, 4, 9), timezone: "America/New_York").and_return(series(candle("2026-04-09T15:00:00Z", close: 18.0)))

    source = described_class.build(config:, start_date: Date.new(2026, 4, 9), end_date: Date.new(2026, 4, 9), adapter: adapter)
    chains = source.chains_at(Time.parse("2026-04-09T15:00:00Z"), expiry_filter: Date.new(2026, 4, 10))

    expect(chains.keys).to eq([Date.new(2026, 4, 10)])
    expect(chains.values.first.call_opts).not_to be_empty
    expect(chains.values.first.put_opts).not_to be_empty
  end

  it "preloads sampled underlying candles without eagerly loading option rows" do
    config = QuantRb::Data::OptionChainConfig.new(
      underlying: "SPX",
      option_root: "SPXW",
      resolution: :minute,
      provider: "test",
      underlying_provider: "test",
      chain_mode: :sampled_interpolated,
      pricing_model: :black_scholes,
      iv_map: nil,
      validation: :repair,
      strike_grid: { step: 5.0, range_ratio: 0.01 }
    )
    rows = [
      { "symbol" => "P1", "contract_type" => "PUT", "strike" => 5100.0, "open" => 14.0, "high" => 16.0, "low" => 13.0, "close" => 15.0, "underlying_price" => nil, "expiration_date" => Date.new(2026, 4, 10), "metadata" => { "sampled_at" => Time.parse("2026-04-09T15:00:00Z"), "expiration_date" => Date.new(2026, 4, 10) } }
    ]
    allow(adapter).to receive(:load_option_chain_rows).and_return(rows)
    allow(adapter).to receive(:load_candle_series).with(provider: "test", ticker: "SPX", resolution: :minute, start_date: Date.new(2026, 4, 9), end_date: Date.new(2026, 4, 9), timezone: "America/New_York").and_return(
      series(candle("2026-04-09T15:00:00Z", close: 5105.0))
    )

    source = described_class.build(config:, start_date: Date.new(2026, 4, 9), end_date: Date.new(2026, 4, 9), adapter: adapter)

    expect(source.preload!).to equal(source)
    expect(adapter).to have_received(:load_candle_series).once
    expect(adapter).not_to have_received(:load_option_chain_rows)
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
      strike_grid: { step: 5.0, range_ratio: 0.01 }
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
    expect(chain.call_opts.map(&:strike).min).to be <= 5030.0
    expect(chain.call_opts.map(&:strike).max).to be >= 5160.0
    expect(chain.all_options.all? { |opt| !opt.mark.nil? }).to be(true)
    expect(chain.all_options.any? { |opt| !opt.delta.nil? }).to be(true)
    interpolated = chain.call_opts.find { |opt| opt.strike == 5105.0 }
    expect(interpolated.days_to_expiration).to eq(1)
    expect(interpolated.intrinsic).not_to be_nil
    expect(interpolated.extrinsic).not_to be_nil
    expect(interpolated.bid).to be < interpolated.ask
    expect(interpolated.symbol).to match(/\ASPXW\s+\d{6}C\d{8}\z/)
  end

  it "hydrates interpolated sampled chains with binomial greeks when configured" do
    config = QuantRb::Data::OptionChainConfig.new(
      underlying: "SPX",
      option_root: "SPXW",
      resolution: :minute,
      provider: "test",
      chain_mode: :sampled_interpolated,
      pricing_model: :binomial,
      iv_map: nil,
      validation: :repair,
      strike_grid: { step: 5.0 }
    )
    sampled_at = Time.parse("2026-04-09T15:00:00Z")
    expiry = Date.new(2026, 4, 10)
    rows = [
      { "symbol" => "C1", "contract_type" => "CALL", "strike" => 5100.0, "open" => 20.0, "high" => 22.0, "low" => 18.0, "close" => 21.0, "underlying_price" => 5105.0, "expiration_date" => expiry, "metadata" => { "sampled_at" => sampled_at, "expiration_date" => expiry } },
      { "symbol" => "C2", "contract_type" => "CALL", "strike" => 5110.0, "open" => 15.0, "high" => 16.0, "low" => 14.0, "close" => 15.5, "underlying_price" => 5105.0, "expiration_date" => expiry, "metadata" => { "sampled_at" => sampled_at, "expiration_date" => expiry } }
    ]
    allow(adapter).to receive(:load_option_chain_rows).and_return(rows)

    source = described_class.build(config:, start_date: Date.new(2026, 4, 9), end_date: Date.new(2026, 4, 9), adapter: adapter)
    chain = source.chains_at(sampled_at, expiry_filter: expiry).fetch(expiry)
    interpolated = chain.call_opts.find { |opt| opt.strike == 5105.0 }

    expect(interpolated.delta).not_to be_nil
    expect(interpolated.gamma).not_to be_nil
    expect(interpolated.theta).not_to be_nil
    expect(interpolated.vega).not_to be_nil
    expect(interpolated.rho).not_to be_nil
  end

  it "derives bid and ask around an OHLC midpoint for sampled interpolated chains" do
    config = QuantRb::Data::OptionChainConfig.new(
      underlying: "SPX",
      option_root: "SPXW",
      resolution: :minute,
      provider: "test",
      chain_mode: :sampled_interpolated,
      pricing_model: :black_scholes,
      iv_map: nil,
      validation: :repair,
      strike_grid: { step: 10.0 }
    )
    sampled_at = Time.parse("2026-04-09T15:00:00Z")
    expiry = Date.new(2026, 4, 10)
    rows = [
      { "symbol" => "P1", "contract_type" => "PUT", "strike" => 5100.0, "open" => 14.0, "high" => 16.0, "low" => 13.0, "close" => 15.0, "underlying_price" => 5105.0, "expiration_date" => expiry, "metadata" => { "sampled_at" => sampled_at, "expiration_date" => expiry } },
      { "symbol" => "P2", "contract_type" => "PUT", "strike" => 5110.0, "open" => 18.0, "high" => 21.0, "low" => 17.0, "close" => 20.0, "underlying_price" => 5105.0, "expiration_date" => expiry, "metadata" => { "sampled_at" => sampled_at, "expiration_date" => expiry } }
    ]
    allow(adapter).to receive(:load_option_chain_rows).and_return(rows)

    source = described_class.build(config:, start_date: Date.new(2026, 4, 9), end_date: Date.new(2026, 4, 9), adapter: adapter)
    chain = source.chains_at(sampled_at, expiry_filter: expiry).fetch(expiry)

    option = chain.put_opts.find { |opt| opt.strike == 5100.0 }
    expect(option.mark).to eq(14.6)
    expect(option.bid).to be < option.ask
    expect(option.bid).to be < option.mark
    expect(option.ask).to be > option.mark
  end

  it "falls back to underlying candle data when sampled rows omit underlying_price" do
    config = QuantRb::Data::OptionChainConfig.new(
      underlying: "SPX",
      option_root: "SPXW",
      resolution: :minute,
      provider: "test",
      chain_mode: :sampled_interpolated,
      pricing_model: :black_scholes,
      iv_map: nil,
      validation: :repair,
      strike_grid: { step: 10.0 }
    )
    sampled_at = Time.parse("2026-04-09T15:00:00Z")
    expiry = Date.new(2026, 4, 10)
    rows = [
      { "symbol" => "P1", "contract_type" => "PUT", "strike" => 5100.0, "open" => 14.0, "high" => 16.0, "low" => 13.0, "close" => 15.0, "underlying_price" => nil, "expiration_date" => expiry, "metadata" => { "sampled_at" => sampled_at, "expiration_date" => expiry } },
      { "symbol" => "P2", "contract_type" => "PUT", "strike" => 5110.0, "open" => 18.0, "high" => 21.0, "low" => 17.0, "close" => 20.0, "underlying_price" => nil, "expiration_date" => expiry, "metadata" => { "sampled_at" => sampled_at, "expiration_date" => expiry } }
    ]
    allow(adapter).to receive(:load_option_chain_rows).and_return(rows)
    allow(adapter).to receive(:load_candle_series).with(provider: "test", ticker: "SPX", resolution: :minute, start_date: Date.new(2026, 4, 9), end_date: Date.new(2026, 4, 9), timezone: "America/New_York").and_return(
      series(candle("2026-04-09T15:00:00Z", close: 5105.0))
    )

    source = described_class.build(config:, start_date: Date.new(2026, 4, 9), end_date: Date.new(2026, 4, 9), adapter: adapter)
    chain = source.chains_at(sampled_at, expiry_filter: expiry).fetch(expiry)

    expect(chain.underlying_price).to eq(5105.0)
    expect(chain.put_opts.all? { |option| option.underlying_price == 5105.0 }).to be(true)
  end

  it "raises a clear error when no underlying candle exists at or before the sampled timestamp" do
    config = QuantRb::Data::OptionChainConfig.new(
      underlying: "SPX",
      option_root: "SPXW",
      resolution: :minute,
      provider: "test",
      chain_mode: :sampled_interpolated,
      pricing_model: :black_scholes,
      iv_map: nil,
      validation: :repair,
      strike_grid: { step: 10.0 }
    )
    sampled_at = Time.parse("2026-04-09T15:00:00Z")
    expiry = Date.new(2026, 4, 10)
    rows = [
      { "symbol" => "P1", "contract_type" => "PUT", "strike" => 5100.0, "open" => 14.0, "high" => 16.0, "low" => 13.0, "close" => 15.0, "underlying_price" => nil, "expiration_date" => expiry, "metadata" => { "sampled_at" => sampled_at, "expiration_date" => expiry } }
    ]
    allow(adapter).to receive(:load_option_chain_rows).and_return(rows)
    allow(adapter).to receive(:load_candle_series).with(provider: "test", ticker: "SPX", resolution: :minute, start_date: Date.new(2026, 4, 9), end_date: Date.new(2026, 4, 9), timezone: "America/New_York").and_return(
      series(candle("2026-04-09T15:01:00Z", close: 5105.0))
    )

    source = described_class.build(config:, start_date: Date.new(2026, 4, 9), end_date: Date.new(2026, 4, 9), adapter: adapter)

    expect do
      source.chains_at(sampled_at, expiry_filter: expiry)
    end.to raise_error(ArgumentError, /at or before/)
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

  it "preserves complete sampled values in validated mode without invoking repair" do
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
      {
        "symbol" => "SPXW  260410C05100000",
        "contract_type" => "CALL",
        "strike" => 5100.0,
        "mark" => 20.0,
        "bid" => 19.5,
        "ask" => 20.5,
        "underlying_price" => 5105.0,
        "expiration_date" => expiry,
        "delta" => 0.51,
        "gamma" => 0.012,
        "theta" => -0.78,
        "vega" => 1.11,
        "rho" => 0.07,
        "volatility" => 19.8,
        "intrinsic_value" => 5.0,
        "extrinsic_value" => 15.0,
        "metadata" => { "sampled_at" => sampled_at, "expiration_date" => expiry }
      }
    ]
    validator = instance_double(QuantRb::Data::Validation::OptionChainValidator)
    allow(validator).to receive(:repair)
    allow(adapter).to receive(:load_option_chain_rows).and_return(rows)

    source = described_class.build(
      config: config,
      start_date: Date.new(2026, 4, 9),
      end_date: Date.new(2026, 4, 9),
      adapter: adapter,
      validator: validator
    )
    chain = source.chains_at(sampled_at, expiry_filter: expiry).fetch(expiry)
    option = chain.call_opts.fetch(0)

    expect(validator).not_to have_received(:repair)
    expect(option.mark).to eq(20.0)
    expect(option.bid).to eq(19.5)
    expect(option.ask).to eq(20.5)
    expect(option.delta).to eq(0.51)
    expect(option.gamma).to eq(0.012)
    expect(option.theta).to eq(-0.78)
    expect(option.vega).to eq(1.11)
    expect(option.rho).to eq(0.07)
    expect(option.volatility).to eq(19.8)
    expect(option.intrinsic).to eq(5.0)
    expect(option.extrinsic).to eq(15.0)
  end

  it "uses per-expiry locf in validated mode without regenerating chains" do
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
    first_sampled_at = Time.parse("2026-04-09T15:00:00Z")
    second_sampled_at = Time.parse("2026-04-09T15:05:00Z")
    expiry = Date.new(2026, 4, 10)
    rows = [
      { "symbol" => "C1", "contract_type" => "CALL", "strike" => 5100.0, "mark" => 20.0, "bid" => 19.5, "ask" => 20.5, "underlying_price" => 5105.0, "expiration_date" => expiry, "metadata" => { "sampled_at" => first_sampled_at, "expiration_date" => expiry } },
      { "symbol" => "P1", "contract_type" => "PUT", "strike" => 5100.0, "mark" => 15.0, "bid" => 14.5, "ask" => 15.5, "underlying_price" => 5105.0, "expiration_date" => expiry, "metadata" => { "sampled_at" => first_sampled_at, "expiration_date" => expiry } },
      { "symbol" => "C1", "contract_type" => "CALL", "strike" => 5100.0, "mark" => 21.0, "bid" => 20.5, "ask" => 21.5, "underlying_price" => 5108.0, "expiration_date" => expiry, "metadata" => { "sampled_at" => second_sampled_at, "expiration_date" => expiry } },
      { "symbol" => "P1", "contract_type" => "PUT", "strike" => 5100.0, "mark" => 14.0, "bid" => 13.5, "ask" => 14.5, "underlying_price" => 5108.0, "expiration_date" => expiry, "metadata" => { "sampled_at" => second_sampled_at, "expiration_date" => expiry } }
    ]
    allow(adapter).to receive(:load_option_chain_rows).and_return(rows)

    source = described_class.build(config:, start_date: Date.new(2026, 4, 9), end_date: Date.new(2026, 4, 9), adapter: adapter)
    first = source.chains_at(first_sampled_at + 30, expiry_filter: expiry).fetch(expiry)
    second = source.chains_at(second_sampled_at + 30, expiry_filter: expiry).fetch(expiry)

    expect(first.call_opts.first.mark).to eq(20.0)
    expect(second.call_opts.first.mark).to eq(21.0)
    expect(source.chains_at(first_sampled_at + 59, expiry_filter: expiry).fetch(expiry).object_id).to eq(first.object_id)
  end

  it "uses localized sampled_at_tz to keep next-day expiries at 1 DTE before local midnight" do
    config = QuantRb::Data::OptionChainConfig.new(
      underlying: "SPX",
      option_root: "SPXW",
      resolution: :minute,
      provider: "test",
      chain_mode: :sampled_validated,
      pricing_model: :black_scholes,
      iv_map: nil,
      validation: :repair,
      strike_grid: { step: 5.0 },
      market_timezone: "America/Chicago"
    )
    sampled_at_utc = Time.parse("2026-04-10T00:30:00Z")
    sampled_at_tz = Time.parse("2026-04-09T19:30:00-05:00")
    expiry = Date.new(2026, 4, 10)
    rows = [
      {
        "sampled_at_utc" => sampled_at_utc,
        "sampled_at_tz" => sampled_at_tz,
        "symbol" => "C1",
        "contract_type" => "CALL",
        "strike" => 5100.0,
        "mark" => 20.0,
        "bid" => 19.5,
        "ask" => 20.5,
        "underlying_price" => 5105.0,
        "expiration_date" => expiry,
        "metadata" => {
          "sampled_at_utc" => sampled_at_utc,
          "sampled_at_tz" => sampled_at_tz,
          "expiration_date" => expiry
        }
      }
    ]
    allow(adapter).to receive(:load_option_chain_rows).and_return(rows)

    source = described_class.build(
      config: config,
      start_date: Date.new(2026, 4, 9),
      end_date: Date.new(2026, 4, 10),
      adapter: adapter
    )
    chain = source.chains_at(sampled_at_tz, expiry_filter: expiry).fetch(expiry)

    expect(chain.call_opts.first.days_to_expiration).to eq(1)
  end

  it "normalizes complete schwab sampled fixtures without adding or mutating contracts" do
    config = QuantRb::Data::OptionChainConfig.new(
      underlying: "SPX",
      option_root: "SPXW",
      resolution: :minute,
      provider: "schwab",
      chain_mode: :sampled_validated,
      pricing_model: :black_scholes,
      iv_map: nil,
      validation: :repair,
      strike_grid: { step: 5.0 }
    )
    rows = fixture_option_rows("SPXW_exp2025-12-18_2025-12-18_13-50-58.csv")
    sampled_at = rows.first.fetch("sampled_at_tz")
    expiry = rows.first.fetch("expiration_date")
    allow(adapter).to receive(:load_option_chain_rows).and_return(rows)

    source = described_class.build(config:, start_date: Date.new(2025, 12, 18), end_date: Date.new(2025, 12, 18), adapter: adapter)
    chain = source.chains_at(sampled_at, expiry_filter: expiry).fetch(expiry)

    expect(chain.call_opts.map(&:symbol)).to eq([rows.first.fetch("symbol")])
    expect(chain.put_opts.map(&:symbol)).to eq([rows.last.fetch("symbol")])
    expect(chain.call_opts.map(&:strike)).to eq([6000.0])
    expect(chain.put_opts.map(&:strike)).to eq([5900.0])
    expect(chain.call_opts.first.volatility).to eq(0.23)
    expect(chain.put_opts.first.delta).to eq(-0.28)
    expect(chain.underlying_price).to eq(6005.0)
  end

  it "uses neighboring spreads for generated strikes instead of collapsing bid and ask to mark" do
    config = QuantRb::Data::OptionChainConfig.new(
      underlying: "SPX",
      option_root: "SPXW",
      resolution: :minute,
      provider: "test",
      chain_mode: :sampled_interpolated,
      pricing_model: :black_scholes,
      iv_map: nil,
      validation: :repair,
      strike_grid: { step: 5.0, range_ratio: 0.01 }
    )
    sampled_at = Time.parse("2026-04-09T15:00:00Z")
    expiry = Date.new(2026, 4, 10)
    rows = [
      { "symbol" => "SPXW  260410C05100000", "contract_type" => "CALL", "strike" => 5100.0, "mark" => 21.0, "bid" => 20.5, "ask" => 21.5, "underlying_price" => 5105.0, "expiration_date" => expiry, "metadata" => { "sampled_at" => sampled_at, "expiration_date" => expiry } },
      { "symbol" => "SPXW  260410C05110000", "contract_type" => "CALL", "strike" => 5110.0, "mark" => 15.5, "bid" => 15.0, "ask" => 16.0, "underlying_price" => 5105.0, "expiration_date" => expiry, "metadata" => { "sampled_at" => sampled_at, "expiration_date" => expiry } }
    ]
    allow(adapter).to receive(:load_option_chain_rows).and_return(rows)

    source = described_class.build(config:, start_date: Date.new(2026, 4, 9), end_date: Date.new(2026, 4, 9), adapter: adapter)
    chain = source.chains_at(sampled_at, expiry_filter: expiry).fetch(expiry)
    interpolated = chain.call_opts.find { |opt| opt.strike == 5105.0 }

    expect(interpolated.bid).to be < interpolated.mark
    expect(interpolated.ask).to be > interpolated.mark
    expect(interpolated.ask - interpolated.bid).to be > 0.05
    expect(interpolated.symbol).to eq("SPXW  260410C05105000")
  end

  it "reprices calls and puts from one shared vol smile so parity is approximately respected" do
    config = QuantRb::Data::OptionChainConfig.new(
      underlying: "SPX",
      option_root: "SPXW",
      resolution: :minute,
      provider: "test",
      chain_mode: :sampled_interpolated,
      pricing_model: :black_scholes,
      iv_map: nil,
      validation: :repair,
      strike_grid: { step: 10.0, range_ratio: 0.01 }
    )
    sampled_at = Time.parse("2026-04-09T15:00:00Z")
    expiry = Date.new(2026, 4, 10)
    rows = [
      { "symbol" => "SPXW  260410C05100000", "contract_type" => "CALL", "strike" => 5100.0, "mark" => 21.0, "bid" => 20.5, "ask" => 21.5, "underlying_price" => 5105.0, "expiration_date" => expiry, "metadata" => { "sampled_at" => sampled_at, "expiration_date" => expiry } },
      { "symbol" => "SPXW  260410P05100000", "contract_type" => "PUT", "strike" => 5100.0, "mark" => 16.0, "bid" => 15.5, "ask" => 16.5, "underlying_price" => 5105.0, "expiration_date" => expiry, "metadata" => { "sampled_at" => sampled_at, "expiration_date" => expiry } },
      { "symbol" => "SPXW  260410C05110000", "contract_type" => "CALL", "strike" => 5110.0, "mark" => 15.5, "bid" => 15.0, "ask" => 16.0, "underlying_price" => 5105.0, "expiration_date" => expiry, "metadata" => { "sampled_at" => sampled_at, "expiration_date" => expiry } },
      { "symbol" => "SPXW  260410P05110000", "contract_type" => "PUT", "strike" => 5110.0, "mark" => 20.5, "bid" => 20.0, "ask" => 21.0, "underlying_price" => 5105.0, "expiration_date" => expiry, "metadata" => { "sampled_at" => sampled_at, "expiration_date" => expiry } }
    ]
    allow(adapter).to receive(:load_option_chain_rows).and_return(rows)

    source = described_class.build(config:, start_date: Date.new(2026, 4, 9), end_date: Date.new(2026, 4, 9), adapter: adapter)
    chain = source.chains_at(sampled_at, expiry_filter: expiry).fetch(expiry)
    strike = 5100.0
    call_option = chain.call_opts.find { |opt| opt.strike == strike }
    put_option = chain.put_opts.find { |opt| opt.strike == strike }
    parity_residual = (call_option.mark - put_option.mark) - (chain.underlying_price - strike)

    expect(parity_residual.abs).to be < 0.15
  end

  it "prefers OTM puts and OTM calls as smile anchors" do
    config = QuantRb::Data::OptionChainConfig.new(
      underlying: "SPX",
      option_root: "SPXW",
      resolution: :minute,
      provider: "test",
      chain_mode: :sampled_interpolated,
      pricing_model: :black_scholes,
      iv_map: nil,
      validation: :repair,
      strike_grid: { step: 10.0, range_ratio: 0.01 }
    )
    sampled_at = Time.parse("2026-04-09T15:00:00Z")
    expiry = Date.new(2026, 4, 10)
    rows = [
      { "symbol" => "SPXW  260410P05080000", "contract_type" => "PUT", "strike" => 5080.0, "mark" => 13.0, "bid" => 12.5, "ask" => 13.5, "underlying_price" => 5105.0, "expiration_date" => expiry, "metadata" => { "sampled_at" => sampled_at, "expiration_date" => expiry } },
      { "symbol" => "SPXW  260410P05120000", "contract_type" => "PUT", "strike" => 5120.0, "mark" => 24.0, "bid" => 23.5, "ask" => 24.5, "underlying_price" => 5105.0, "expiration_date" => expiry, "metadata" => { "sampled_at" => sampled_at, "expiration_date" => expiry } },
      { "symbol" => "SPXW  260410C05080000", "contract_type" => "CALL", "strike" => 5080.0, "mark" => 31.0, "bid" => 30.5, "ask" => 31.5, "underlying_price" => 5105.0, "expiration_date" => expiry, "metadata" => { "sampled_at" => sampled_at, "expiration_date" => expiry } },
      { "symbol" => "SPXW  260410C05120000", "contract_type" => "CALL", "strike" => 5120.0, "mark" => 14.0, "bid" => 13.5, "ask" => 14.5, "underlying_price" => 5105.0, "expiration_date" => expiry, "metadata" => { "sampled_at" => sampled_at, "expiration_date" => expiry } }
    ]
    allow(adapter).to receive(:load_option_chain_rows).and_return(rows)

    source = described_class.build(config:, start_date: Date.new(2026, 4, 9), end_date: Date.new(2026, 4, 9), adapter: adapter)
    chain = source.chains_at(sampled_at, expiry_filter: expiry).fetch(expiry)
    downside_call = chain.call_opts.find { |opt| opt.strike == 5090.0 }
    upside_call = chain.call_opts.find { |opt| opt.strike == 5110.0 }
    downside_put = chain.put_opts.find { |opt| opt.strike == 5090.0 }
    upside_put = chain.put_opts.find { |opt| opt.strike == 5110.0 }

    expect(downside_call.volatility).to be > upside_call.volatility
    expect(downside_put.volatility).to be > upside_put.volatility
  end

  it "returns generated chains that remain convex by strike after repair" do
    config = QuantRb::Data::OptionChainConfig.new(
      underlying: "SPX",
      option_root: "SPXW",
      resolution: :minute,
      provider: "test",
      chain_mode: :sampled_interpolated,
      pricing_model: :black_scholes,
      iv_map: nil,
      validation: :repair,
      strike_grid: { step: 5.0, range_ratio: 0.01 }
    )
    sampled_at = Time.parse("2026-04-09T15:00:00Z")
    expiry = Date.new(2026, 4, 10)
    rows = [
      { "symbol" => "SPXW  260410C05100000", "contract_type" => "CALL", "mark" => 21.0, "bid" => 20.5, "ask" => 21.5, "strike" => 5100.0, "underlying_price" => 5105.0, "expiration_date" => expiry, "metadata" => { "sampled_at" => sampled_at, "expiration_date" => expiry } },
      { "symbol" => "SPXW  260410P05100000", "contract_type" => "PUT", "mark" => 16.0, "bid" => 15.5, "ask" => 16.5, "strike" => 5100.0, "underlying_price" => 5105.0, "expiration_date" => expiry, "metadata" => { "sampled_at" => sampled_at, "expiration_date" => expiry } },
      { "symbol" => "SPXW  260410C05110000", "contract_type" => "CALL", "mark" => 15.5, "bid" => 15.0, "ask" => 16.0, "strike" => 5110.0, "underlying_price" => 5105.0, "expiration_date" => expiry, "metadata" => { "sampled_at" => sampled_at, "expiration_date" => expiry } },
      { "symbol" => "SPXW  260410P05110000", "contract_type" => "PUT", "mark" => 20.5, "bid" => 20.0, "ask" => 21.0, "strike" => 5110.0, "underlying_price" => 5105.0, "expiration_date" => expiry, "metadata" => { "sampled_at" => sampled_at, "expiration_date" => expiry } }
    ]
    allow(adapter).to receive(:load_option_chain_rows).and_return(rows)

    source = described_class.build(config:, start_date: Date.new(2026, 4, 9), end_date: Date.new(2026, 4, 9), adapter: adapter)
    chain = source.chains_at(sampled_at, expiry_filter: expiry).fetch(expiry)

    [chain.call_opts, chain.put_opts].each do |options|
      options.each_cons(3) do |left, middle, right|
        upper_bound = left.mark + ((right.mark - left.mark) * ((middle.strike - left.strike) / (right.strike - left.strike).to_f))
        expect(middle.mark).to be <= upper_bound + 1e-4
      end
    end
  end

  it "reuses the same reconstructed chain when multiple target times map to the same sampled snapshot" do
    config = QuantRb::Data::OptionChainConfig.new(
      underlying: "SPX",
      option_root: "SPXW",
      resolution: :minute,
      provider: "test",
      chain_mode: :sampled_interpolated,
      pricing_model: :black_scholes,
      iv_map: nil,
      validation: :repair,
      strike_grid: { step: 10.0, range_ratio: 0.01 }
    )
    sampled_at = Time.parse("2026-04-09T15:00:00Z")
    expiry = Date.new(2026, 4, 10)
    rows = [
      { "symbol" => "SPXW  260410P05100000", "contract_type" => "PUT", "strike" => 5100.0, "open" => 14.0, "high" => 16.0, "low" => 13.0, "close" => 15.0, "underlying_price" => 5105.0, "expiration_date" => expiry, "metadata" => { "sampled_at" => sampled_at, "expiration_date" => expiry } },
      { "symbol" => "SPXW  260410C05110000", "contract_type" => "CALL", "strike" => 5110.0, "open" => 15.0, "high" => 16.0, "low" => 14.0, "close" => 15.5, "underlying_price" => 5105.0, "expiration_date" => expiry, "metadata" => { "sampled_at" => sampled_at, "expiration_date" => expiry } }
    ]
    allow(adapter).to receive(:load_option_chain_rows).and_return(rows)

    source = described_class.build(config:, start_date: Date.new(2026, 4, 9), end_date: Date.new(2026, 4, 9), adapter: adapter)
    first = source.chains_at(sampled_at, expiry_filter: expiry).fetch(expiry)
    second = source.chains_at(sampled_at + 30, expiry_filter: expiry).fetch(expiry)

    expect(first.object_id).to eq(second.object_id)
  end
end
