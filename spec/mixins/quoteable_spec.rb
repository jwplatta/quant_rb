# frozen_string_literal: true

require 'rspec'
require_relative '../../mixins/quoteable'
require_relative '../../mixins/schwab/data_objects/quote'

RSpec.describe Quoteable do
  let(:test_class) do
    Class.new do
      include Quoteable

      def symbol
        'AAPL'
      end
    end
  end

  let(:quoteable_instance) { test_class.new }
  let(:mock_quote) do
    instance_double('DataObjects::OptionQuote',
                    strike_price: 150.0,
                    delta: 0.5,
                    mark: 149.5,
                    ask_price: 150.5,
                    bid_price: 149.0,
                    expiration_year: 2025,
                    expiration_month: 6,
                    expiration_day: 20)
  end

  before do
    quoteable_instance.initialize_quoteable
    quoteable_instance.instance_variable_set(:@quote, mock_quote)
  end

  describe '#strike' do
    it 'returns the strike price from the quote' do
      expect(quoteable_instance.strike).to eq(150.0)
    end
  end

  describe '#delta' do
    it 'returns the absolute value of the delta from the quote' do
      expect(quoteable_instance.delta).to eq(0.5)
    end
  end

  describe '#mark' do
    it 'returns the mark price from the quote' do
      expect(quoteable_instance.mark).to eq(149.5)
    end
  end

  describe '#ask' do
    it 'returns the ask price from the quote' do
      expect(quoteable_instance.ask).to eq(150.5)
    end
  end

  describe '#bid' do
    it 'returns the bid price from the quote' do
      expect(quoteable_instance.bid).to eq(149.0)
    end
  end

  describe '#expiration_date' do
    it 'returns the expiration date from the quote' do
      expect(quoteable_instance.expiration_date).to eq(Date.new(2025, 6, 20))
    end
  end
end