# frozen_string_literal: true

require 'rspec'

RSpec.describe OptionsTrader::Quoteable do
  let(:test_class) do
    Class.new do
      include OptionsTrader::Quoteable

      def symbol
        'AAPL'
      end
    end
  end

  let(:quoteable_instance) { test_class.new }
  let(:mock_quote) do
    instance_double('OptionsTrader::Schwab::DataObjects::OptionQuote',
                    strike_price: 150.0,
                    delta: 0.5,
                    mark: 149.5,
                    ask_price: 150.5,
                    bid_price: 149.0,
                    expiration_year: 2025,
                    expiration_month: 6,
                    expiration_day: 20,
                    open_interest: 1000)
  end

  before do
    # Mock the quote method from the Schwab module
    allow(quoteable_instance).to receive(:quote).with('AAPL').and_return(mock_quote)
    quoteable_instance.check_market
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

  describe '#open_interest' do
    it 'returns the open interest from the quote' do
      expect(quoteable_instance.open_interest).to eq(1000)
    end
  end

  describe '#check_market' do
    it 'fetches and sets quote data' do
      # Reset the instance
      new_instance = test_class.new
      expect(new_instance.strike).to be_nil

      # Mock a new quote
      new_quote = instance_double('OptionsTrader::Schwab::DataObjects::OptionQuote',
                                  strike_price: 155.0,
                                  delta: -0.3,
                                  mark: 154.5,
                                  ask_price: 155.5,
                                  bid_price: 154.0,
                                  expiration_year: 2025,
                                  expiration_month: 7,
                                  expiration_day: 18,
                                  open_interest: 2000)

      allow(new_instance).to receive(:quote).with('AAPL').and_return(new_quote)

      new_instance.check_market

      expect(new_instance.strike).to eq(155.0)
      expect(new_instance.delta).to eq(0.3)  # Should be absolute value
      expect(new_instance.mark).to eq(154.5)
      expect(new_instance.ask).to eq(155.5)
      expect(new_instance.bid).to eq(154.0)
      expect(new_instance.expiration_date).to eq(Date.new(2025, 7, 18))
      expect(new_instance.open_interest).to eq(2000)
    end

    it 'handles nil delta gracefully' do
      quote_with_nil_delta = instance_double('OptionsTrader::Schwab::DataObjects::OptionQuote',
                                             strike_price: 150.0,
                                             delta: nil,
                                             mark: 149.5,
                                             ask_price: 150.5,
                                             bid_price: 149.0,
                                             expiration_year: 2025,
                                             expiration_month: 6,
                                             expiration_day: 20,
                                             open_interest: 1000)

      new_instance = test_class.new
      allow(new_instance).to receive(:quote).with('AAPL').and_return(quote_with_nil_delta)

      new_instance.check_market

      expect(new_instance.delta).to eq(999)  # Default value when delta is nil
    end

    it 'handles quote fetch errors gracefully' do
      new_instance = test_class.new
      allow(new_instance).to receive(:quote).with('AAPL').and_raise(StandardError.new('API Error'))

      expect { new_instance.check_market }.not_to raise_error
      expect(new_instance.strike).to be_nil
    end
  end

  describe '#market_change?' do
    it 'returns false when no last_quote exists' do
      new_instance = test_class.new
      expect(new_instance.market_change?).to be false
    end

    it 'returns true when mark price has changed significantly' do
      # Set up initial quote
      quoteable_instance.instance_variable_set(:@last_quote, mock_quote)

      # Mock a new quote with significant price change
      new_quote = instance_double('OptionsTrader::Schwab::DataObjects::OptionQuote',
                                  strike_price: 150.0,
                                  delta: 0.5,
                                  mark: 160.0,  # More than 5% change from 149.5
                                  ask_price: 160.5,
                                  bid_price: 159.0,
                                  expiration_year: 2025,
                                  expiration_month: 6,
                                  expiration_day: 20,
                                  open_interest: 1000)

      allow(quoteable_instance).to receive(:quote).with('AAPL').and_return(new_quote)

      expect(quoteable_instance.market_change?).to be true
    end

    it 'returns false when mark price change is less than 5%' do
      # Set up initial quote
      quoteable_instance.instance_variable_set(:@last_quote, mock_quote)

      # Mock a new quote with small price change
      new_quote = instance_double('OptionsTrader::Schwab::DataObjects::OptionQuote',
                                  strike_price: 150.0,
                                  delta: 0.5,
                                  mark: 150.0,  # Less than 5% change from 149.5
                                  ask_price: 150.5,
                                  bid_price: 149.5,
                                  expiration_year: 2025,
                                  expiration_month: 6,
                                  expiration_day: 20,
                                  open_interest: 1000)

      allow(quoteable_instance).to receive(:quote).with('AAPL').and_return(new_quote)

      expect(quoteable_instance.market_change?).to be false
    end
  end
end