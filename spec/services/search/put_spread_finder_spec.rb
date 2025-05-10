# frozen_string_literal: true

require 'rspec'
require 'pry'
require_relative '../../../services/search/put_spread_finder'
require_relative '../../../mixins/schwab/data_objects/option_chain'

RSpec.describe Services::Search::PutSpreadFinder do
  let(:acme_put_options) do
    JSON.parse(File.read('spec/fixtures/option_chains/ACME_puts.json'), symbolize_names: true).then do |data|
      DataObjects::OptionChain.build(data)
    end
  end
  describe '#search' do
    it 'returns a list of put spreads' do
      finder = Services::Search::PutSpreadFinder.new(
        symbol: 'ACME',
        opt_chain: acme_put_options,
        end_date: Date.new(2025, 1, 17)
      )
      best_trade = finder.search
      expect(best_trade.short_leg.strike).to eq 75.0
      expect(best_trade.long_leg.strike).to eq 70.0
      expect(best_trade.short_leg.expiration_date).to eq best_trade.long_leg.expiration_date
    end
  end
end
