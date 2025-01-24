require 'rspec'
require_relative '../../models/option_chain'

RSpec.describe OptionChain do
  let(:raw_data) do
    JSON.parse(File.read('spec/fixtures/option_chains/AAPL.json'), symbolize_names: true)
  end
  describe '.build' do
    it 'creates an option chain object from raw data' do
      option_chain = OptionChain.build(raw_data)
      expect(option_chain).to be_an_instance_of OptionChain
      expect(option_chain.symbol).to eq 'AAPL'
    end
  end

  describe '#filter' do
    it 'use the absolute value of delta to filter the options chain' do
      option_chain = OptionChain.build(raw_data)

      filters = [
        OptionFilter.new(attribute: :delta, comparison: "<=", value: 0.15),
      ]

      filtered_puts = option_chain.filter(put_call: :put, filters: filters)
      expect(filtered_puts).to be_an_instance_of Array
      filtered_puts.each do |put|
        expect(put).to be_an_instance_of Option
        expect(put.delta.abs).to be <= 0.15
      end
    end
    it 'filters the options chain based on the open interest' do
      option_chain = OptionChain.build(raw_data)
      filters = [
        OptionFilter.new(attribute: :open_interest, comparison: ">", value: 0),
      ]

      filtered_puts = option_chain.filter(put_call: :put, filters: filters)
      expect(filtered_puts).to be_an_instance_of Array
      filtered_puts.each do |put|
        expect(put).to be_an_instance_of Option
        expect(put.open_interest).to be > 0
      end
    end
  end
end
