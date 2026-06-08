# frozen_string_literal: true

require "spec_helper"

RSpec.describe "QuantRb data layer integration", :integration do
  let(:history_path) { File.expand_path("~/.tickrake/data/history/schwab") }
  let(:options_path) { File.expand_path("~/.tickrake/data/options/schwab") }

  def parse_filename_timestamp_utc(sample_date, sample_time)
    Time.strptime("#{sample_date} #{sample_time.tr('-', ':')} UTC", "%Y-%m-%d %H:%M:%S %Z").utc
  end

  before do
    skip "tickrake history data not available" unless File.exist?(File.join(history_path, "SPX_1min.csv"))
    skip "tickrake options data not available" if Dir.glob(File.join(options_path, "**", "SPXW_exp*.csv")).empty?
  end

  it "loads real candle data from the configured history path" do
    series = QuantRb::Data::Series::CandleLoader.load(
      symbol: "SPX",
      resolution: :minute,
      data_path: history_path
    )
    candle = series[0]

    expect(series).not_to be_empty
    expect(candle).to be_a(QuantRb::DataObjects::Candle)
    expect(candle.datetime).to be_a(Time)
    expect(candle.close).to be_a(Float)
  end

  it "loads sampled SPXW chains through the tickrake-backed option chain source" do
    file_path = Dir.glob(File.join(options_path, "**", "SPXW_exp*.csv")).sort.first
    filename = File.basename(file_path)
    match = filename.match(/\ASPXW_exp(?<expiry>\d{4}-\d{2}-\d{2})_(?<sample_date>\d{4}-\d{2}-\d{2})_(?<sample_time>\d{2}-\d{2}-\d{2})\.csv\z/)
    raise "Unexpected fixture filename: #{filename}" unless match

    sample_time_utc = parse_filename_timestamp_utc(match[:sample_date], match[:sample_time])
    sample_time = sample_time_utc.getlocal("-05:00") + 1
    expiry = Date.parse(match[:expiry])
    source = QuantRb::Data::OptionChainSource.build(
      config: QuantRb::Data::OptionChainConfig.new(
        underlying: "SPX",
        option_root: "SPXW",
        resolution: :minute,
        provider: "schwab",
        chain_mode: :sampled_validated,
        pricing_model: :black_scholes,
        iv_map: nil,
        validation: :repair,
        strike_grid: {},
        market_timezone: "America/Chicago"
      ),
      start_date: sample_time.to_date,
      end_date: sample_time.to_date
    )
    chains = source.chains_at(sample_time)

    expect(chains).not_to be_empty
    expect(chains[expiry]).to be_a(QuantRb::DataObjects::OptionsChain)
    expect(chains[expiry].all_options).not_to be_empty
    option = chains[expiry].all_options.find { |opt| !opt.delta.nil? && !opt.gamma.nil? && !opt.theta.nil? && !opt.vega.nil? && !opt.rho.nil? }
    expect(option).not_to be_nil
  end
end
