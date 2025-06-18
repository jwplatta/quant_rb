# frozen_string_literal: true

require 'rspec'

RSpec.describe DataObjects::OptionChain do
  let(:raw_data) do
    JSON.parse(File.read('spec/fixtures/option_chains/AAPL.json'), symbolize_names: true)
  end
  
  describe '.build' do
    it 'creates an option chain object from raw data' do
      option_chain = DataObjects::OptionChain.build(raw_data)
      expect(option_chain).to be_an_instance_of DataObjects::OptionChain
      expect(option_chain.symbol).to eq 'AAPL'
    end
  end
end
