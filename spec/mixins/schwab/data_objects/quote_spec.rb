# frozen_string_literal: true

require 'rspec'
require_relative '../../../../mixins/schwab/data_objects/quote'

RSpec.describe DataObjects::QuoteFactory do
  let(:option_quote_data) do
    JSON.parse(
      File.read(
        'spec/fixtures/quotes/NVDA  250307P00095000_quote.json'
      ),
      symbolize_names: true
    )
  end

  let(:equity_quote_data) do
    JSON.parse(
      File.read(
        'spec/fixtures/quotes/NVDA_quote.json'
      ),
      symbolize_names: true
    )
  end

  let(:index_quote_data) do
    JSON.parse(
      File.read(
        'spec/fixtures/quotes/$SPX_quote.json'
      ),
      symbolize_names: true
    )
  end

  describe '.build' do
    it 'creates an option quote' do
      quote = DataObjects::QuoteFactory.build(option_quote_data)
      expect(quote).to be_an_instance_of(DataObjects::OptionQuote)
      expect(quote.symbol).to eq('NVDA  250307P00095000')
    end

    it 'creates an index quote' do
      quote = DataObjects::QuoteFactory.build(index_quote_data)
      expect(quote).to be_an_instance_of(DataObjects::IndexQuote)
      expect(quote.symbol).to eq('$SPX')
    end

    it 'creates an equity quote' do
      quote = DataObjects::QuoteFactory.build(equity_quote_data)
      expect(quote).to be_an_instance_of(DataObjects::EquityQuote)
      expect(quote.symbol).to eq('NVDA')
    end

    it 'raises an error if the quote type is not recognized' do
      invalid_data = { 'SYMBOL' => { assetMainType: 'UNKNOWN' } }
      expect { DataObjects::QuoteFactory.build(invalid_data) }.to raise_error('Unknown assetMainType: UNKNOWN')
    end
  end
end
