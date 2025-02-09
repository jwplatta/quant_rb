require "rspec"
require "pry"
require_relative "../../../services/search/spread_finder"
require_relative "../../../models/option_chain"

RSpec.describe SpreadFinder do
  let(:acme_call_options) do
    JSON.parse(File.read("spec/fixtures/option_chains/ACME_calls.json"), symbolize_names: true).then do |data|
      OptionChain.build(data)
    end
  end
  let(:acme_put_options) do
    JSON.parse(File.read("spec/fixtures/option_chains/ACME_puts.json"), symbolize_names: true).then do |data|
      OptionChain.build(data)
    end
  end
  fdescribe "#search" do
    it "returns a list of call spreads" do
      allow_any_instance_of(SpreadFinder).to receive(:option_chain).and_return(acme_call_options)
      finder = SpreadFinder.new(symbol: "ACME", contract_type: "CALL")
      trades = finder.search
      expect(trades.count).to eq 1
      expect(trades.first.short_leg.strike).to eq 125.0
      expect(trades.first.long_leg.strike).to eq 130.0
    end
    it "returns a list of put spreads" do
      allow_any_instance_of(SpreadFinder).to receive(:option_chain).and_return(acme_put_options)
      finder = SpreadFinder.new(symbol: "ACME", contract_type: "PUT")
      trades = finder.search
      expect(trades.count).to eq 1
      expect(trades.first.short_leg.strike).to eq 75.0
      expect(trades.first.long_leg.strike).to eq 70.0
    end
  end
end
