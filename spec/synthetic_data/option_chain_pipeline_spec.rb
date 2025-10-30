require 'spec_helper'

RSpec.xdescribe OptionsTrader::SyntheticData::OptionChainPipeline do
  include_context 'realistic SPX option chain'

  describe 'basic pipeline integration' do
    it 'runs full pipeline and returns valid option chain' do
      result = described_class.new(option_chain)
        .with_features(features)
        .enforce_monotonicity(method: 'remove')
        .complete_strikes(min_strike: 5800, max_strike: 8000)
        .interpolate_prices(min_extrinsic: 0.025)
        .build

      expect(result).to be_a(OptionsTrader::DataObjects::OptionsChain)
      expect(result.call_opts.length).to be > call_opts.length
      expect(result.put_opts.length).to be > put_opts.length
    end

    it 'adds synthetic strikes' do
      result = described_class.new(option_chain)
        .with_features(features)
        .complete_strikes(min_strike: 5800, max_strike: 8000)
        .build

      expect(result.call_opts.length).to be > call_opts.length
      expect(result.put_opts.length).to be > put_opts.length
    end

    it 'interpolates prices for synthetic options' do
      result = described_class.new(option_chain)
        .with_features(features)
        .complete_strikes(min_strike: 5800, max_strike: 8000)
        .interpolate_prices
        .build

      all_have_prices = result.call_opts.all? { |opt| opt.mark && opt.mark > 0 }
      expect(all_have_prices).to be true
    end
  end
end
