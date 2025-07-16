# frozen_string_literal: true

require 'spec_helper'

RSpec.describe OptionsTrader::CallOption do
  let(:call_option) { described_class.new('SPY250620C00500000', quantity: 5) }

  before do
    allow(call_option).to receive(:mark).and_return(2.50)
  end

  describe '#initialize' do
    it 'sets symbol and quantity' do
      expect(call_option.symbol).to eq('SPY250620C00500000')
      expect(call_option.quantity).to eq(5)
    end

    it 'uses default quantity of 1' do
      option = described_class.new('SPY250620C00500000')
      expect(option.quantity).to eq(1)
    end

    it 'accepts custom increment and round values' do
      option = described_class.new('SPY250620C00500000', quantity: 2, increment: 0.05, round: 3)
      expect(option.increment).to eq(0.05)
      expect(option.round).to eq(3)
    end
  end

  describe '.from_schwab_option' do
    let(:schwab_option) do
      double('SchwabOption',
        symbol: 'SPY250620C00500000',
        strike: 500.0,
        delta: 0.25,
        mark: 2.50,
        ask: 2.55,
        bid: 2.45,
        expiration_date: Date.new(2025, 6, 20),
        open_interest: 1000
      )
    end

    it 'creates CallOption from schwab option data' do
      option = described_class.from_schwab_option(schwab_option, quantity: 3)

      expect(option.symbol).to eq('SPY250620C00500000')
      expect(option.quantity).to eq(3)
      expect(option.strike).to eq(500.0)
      expect(option.delta).to eq(0.25)
      expect(option.mark).to eq(2.50)
      expect(option.ask).to eq(2.55)
      expect(option.bid).to eq(2.45)
      expect(option.expiration_date).to eq(Date.new(2025, 6, 20))
      expect(option.open_interest).to eq(1000)
    end

    it 'uses default quantity of 1' do
      option = described_class.from_schwab_option(schwab_option)
      expect(option.quantity).to eq(1)
    end
  end

  describe '#credit' do
    it 'returns mark price rounded to nearest increment' do
      expect(call_option.credit).to eq(2.50)
    end

    it 'rounds to nearest increment' do
      allow(call_option).to receive(:mark).and_return(2.53)
      expect(call_option.credit).to eq(2.53)
    end
  end

  describe '#debit' do
    it 'returns negative mark price rounded to nearest increment' do
      expect(call_option.debit).to eq(-2.50)
    end
  end

  describe '#short?' do
    it 'returns true when quantity is negative' do
      short_option = described_class.new('SPY250620C00500000', quantity: -5)
      expect(short_option.short?).to be true
    end

    it 'returns false when quantity is positive' do
      expect(call_option.short?).to be false
    end
  end

  describe '#long?' do
    it 'returns true when quantity is positive' do
      expect(call_option.long?).to be true
    end

    it 'returns false when quantity is negative' do
      short_option = described_class.new('SPY250620C00500000', quantity: -5)
      expect(short_option.long?).to be false
    end
  end

  describe 'inheritance' do
    it 'inherits from StrategyBase' do
      expect(call_option).to be_a(OptionsTrader::StrategyBase)
    end

    it 'includes Quoteable module' do
      expect(described_class.included_modules).to include(OptionsTrader::Quoteable)
    end
  end
end