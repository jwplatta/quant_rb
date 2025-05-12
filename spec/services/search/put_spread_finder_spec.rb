# frozen_string_literal: true

require 'rspec'
require 'pry'
require_relative '../../../services/search/put_spread_finder'
require_relative '../../../mixins/schwab/data_objects/option_chain'

RSpec.describe Services::Search::PutSpreadFinder do
  let(:spx_put_options) do
    JSON.parse(File.read('spec/fixtures/option_chains/SPX_05_20_2025_option_chain.json'), symbolize_names: true).then do |data|
      DataObjects::OptionChain.build(data)
    end
  end
  describe '#search' do
    it 'returns a put spread' do
      finder = Services::Search::PutSpreadFinder.new(
        symbol: '$SPX',
        expiration_date: Date.new(2025, 5, 20),
        short_delta: 0.05,
        max_spread: 25.0,
        min_credit: 10.0,
        min_open_interest: 0,
        dist_from_strike: 0.01,
        opt_chain: spx_put_options,
        quantity: 1
      )
      best_trade = finder.search
      expect(best_trade.spread_width).to be <= finder.max_spread
      expect(best_trade.short_leg.delta).to be <= finder.short_delta
      expect(best_trade.credit_debit * 100).to be >= finder.min_credit
    end
    it 'returns a put spread with a high min credit' do
      finder = Services::Search::PutSpreadFinder.new(
        symbol: '$SPX',
        expiration_date: Date.new(2025, 5, 20),
        short_delta: 0.08,
        max_spread: 25.0,
        min_credit: 100.0,
        min_open_interest: 0,
        dist_from_strike: 0.01,
        opt_chain: spx_put_options,
        quantity: 1
      )
      best_trade = finder.search
      expect(best_trade.spread_width).to be <= finder.max_spread
      expect(best_trade.short_leg.delta).to be <= finder.short_delta
      expect(best_trade.credit_debit * 100).to be >= finder.min_credit
    end
  end
end
