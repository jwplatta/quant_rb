require "rspec"
require "pry"
require_relative "../../../services/search/spread_finder"
require_relative "../../../services/schwab/data_objects/option_chain"

RSpec.describe SpreadFinder do
  let(:acme_call_options) do
    JSON.parse(File.read("spec/fixtures/option_chains/ACME_calls.json"), symbolize_names: true).then do |data|
      DataObjects::OptionChain.build(data)
    end
  end
  let(:acme_put_options) do
    JSON.parse(File.read("spec/fixtures/option_chains/ACME_puts.json"), symbolize_names: true).then do |data|
      DataObjects::OptionChain.build(data)
    end
  end
  describe "#search" do
    it "returns a list of call spreads" do
      finder = SpreadFinder.new(
        symbol: "ACME",
        contract_type: "CALL",
        option_chain: acme_call_options,
        end_date: Date.new(2025, 1, 17)
      )
      best_trade = finder.search
      expect(best_trade.short_leg.strike).to eq 125.0
      expect(best_trade.long_leg.strike).to eq 130.0
      expect(best_trade.short_leg.expiration_date).to eq best_trade.long_leg.expiration_date
    end
    it "returns a list of put spreads" do
      finder = SpreadFinder.new(
        symbol: "ACME",
        contract_type: "PUT",
        option_chain: acme_put_options,
        end_date: Date.new(2025, 1, 17)
      )
      best_trade = finder.search
      expect(best_trade.short_leg.strike).to eq 75.0
      expect(best_trade.long_leg.strike).to eq 70.0
      expect(best_trade.short_leg.expiration_date).to eq best_trade.long_leg.expiration_date
    end
    context "when given an expiration date" do
      it "returns a list of call spreads" do
        finder = SpreadFinder.new(
          symbol: "ACME",
          contract_type: "CALL",
          option_chain: acme_call_options,
          min_credit: 50.0,
          expiration_date: Date.new(2025, 1, 16)
        )
        best_trade = finder.search

        expect(best_trade.short_leg.strike).to eq 125.0
        expect(best_trade.long_leg.strike).to eq 130.0
        expect(best_trade.short_leg.expiration_date).to eq Date.new(2025, 1, 16)
        expect(best_trade.short_leg.expiration_date).to eq best_trade.long_leg.expiration_date
      end
    end
  end
end