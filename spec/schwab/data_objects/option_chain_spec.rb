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

  describe '#filter' do
    it 'use the absolute value of delta to filter the options chain' do
      option_chain = DataObjects::OptionChain.build(raw_data)

      filters = [
        [:delta, '<=', 0.15]
      ]

      filtered_puts = option_chain.filter(put_call: :put, filters: filters)
      expect(filtered_puts).to be_an_instance_of Array
      filtered_puts.each do |put|
        expect(put).to be_an_instance_of DataObjects::Option
        expect(put.delta.abs).to be <= 0.15
      end
    end
    it 'filters the options chain based on the open interest' do
      option_chain = DataObjects::OptionChain.build(raw_data)
      filters = [
        [:open_interest, '>', 0]
      ]

      filtered_puts = option_chain.filter(put_call: :put, filters: filters)
      expect(filtered_puts).to be_an_instance_of Array
      filtered_puts.each do |put|
        expect(put).to be_an_instance_of DataObjects::Option
        expect(put.open_interest).to be > 0
      end
    end
  end
end
