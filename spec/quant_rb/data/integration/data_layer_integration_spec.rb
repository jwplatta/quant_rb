# frozen_string_literal: true

require "spec_helper"

RSpec.describe "QuantRb data layer integration", :integration do
  let(:history_path) { File.expand_path("~/.tickrake/data/history/schwab") }
  let(:options_path) { File.expand_path("~/.tickrake/data/options/schwab") }

  before do
    skip "tickrake history data not available" unless File.exist?(File.join(history_path, "SPX_1min.csv"))
    skip "tickrake options data not available" if Dir.glob(File.join(options_path, "SPXW_exp*.csv")).empty?
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

  it "loads a real SPXW options chain with populated greeks" do
    file_path = Dir.glob(File.join(options_path, "SPXW_exp*.csv")).sort.first
    chain = QuantRb::Data::Loaders::CsvOptionsChain.load(file_path)

    expect(chain).to be_a(QuantRb::DataObjects::OptionsChain)
    expect(chain).not_to be_empty

    option = chain.all_options.find { |opt| !opt.delta.nil? && !opt.gamma.nil? && !opt.theta.nil? && !opt.vega.nil? && !opt.rho.nil? }
    expect(option).not_to be_nil
    expect(option.delta).to be_a(Float)
    expect(option.gamma).to be_a(Float)
    expect(option.theta).to be_a(Float)
    expect(option.vega).to be_a(Float)
    expect(option.rho).to be_a(Float)
  end

  it "indexes real SPXW chain files and returns locf chains at a sampled time" do
    file_path = Dir.glob(File.join(options_path, "SPXW_exp*.csv")).sort.first
    filename = File.basename(file_path)
    match = filename.match(/\ASPXW_exp(?<expiry>\d{4}-\d{2}-\d{2})_(?<sample_date>\d{4}-\d{2}-\d{2})_(?<sample_time>\d{2}-\d{2}-\d{2})\.csv\z/)
    raise "Unexpected fixture filename: #{filename}" unless match

    sample_time = Time.parse("#{match[:sample_date]} #{match[:sample_time].tr('-', ':')}") + 1
    expiry = Date.parse(match[:expiry])

    index = QuantRb::Data::Index::OptionsChainIndex.new(root_path: options_path, symbol: "SPXW")
    chains = index.chains_at(sample_time)

    expect(chains).not_to be_empty
    expect(chains[expiry]).to be_a(QuantRb::DataObjects::OptionsChain)
    expect(chains[expiry].all_options).not_to be_empty
  end
end
