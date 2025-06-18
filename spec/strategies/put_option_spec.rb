# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Platypi::PutOption do
  let(:put_option) { described_class.new('SPY250620P00450000', quantity: 3) }

  before do
    allow(put_option).to receive(:mark).and_return(1.75)
  end

  describe '#initialize' do
    it 'sets symbol and quantity' do
      expect(put_option.symbol).to eq('SPY250620P00450000')
      expect(put_option.quantity).to eq(3)
    end

    it 'uses default quantity of 1' do
      option = described_class.new('SPY250620P00450000')

      expect(option.quantity).to eq(1)
    end

    it 'accepts custom increment and round values' do
      option = described_class.new('SPY250620P00450000', quantity: 2, increment: 0.05, round: 3)

      expect(option.increment).to eq(0.05)
      expect(option.round).to eq(3)
    end
  end

  describe '.from_schwab_option' do
    let(:schwab_option) do
      double('SchwabOption',
        symbol: 'SPY250620P00450000',
        strike: 450.0,
        delta: -0.15,
        mark: 1.75,
        ask: 1.80,
        bid: 1.70,
        expiration_date: Date.new(2025, 6, 20),
        open_interest: 800
      )
    end

    it 'creates PutOption from schwab option data' do
      option = described_class.from_schwab_option(schwab_option, quantity: 2)

      expect(option.symbol).to eq('SPY250620P00450000')
      expect(option.quantity).to eq(2)
      expect(option.strike).to eq(450.0)
      expect(option.delta).to eq(-0.15)
      expect(option.mark).to eq(1.75)
      expect(option.ask).to eq(1.80)
      expect(option.bid).to eq(1.70)
      expect(option.expiration_date).to eq(Date.new(2025, 6, 20))
      expect(option.open_interest).to eq(800)
    end

    it 'uses default quantity of 1' do
      option = described_class.from_schwab_option(schwab_option)
      expect(option.quantity).to eq(1)
    end
  end

  describe '#credit' do
    it 'returns mark price rounded to nearest increment' do
      expect(put_option.credit).to eq(1.75)
    end

    it 'rounds to nearest increment' do
      allow(put_option).to receive(:mark).and_return(1.73)
      expect(put_option.credit).to eq(1.73)
    end
  end

  describe '#debit' do
    it 'returns negative mark price rounded to nearest increment' do
      expect(put_option.debit).to eq(-1.75)
    end
  end

  describe '#short?' do
    it 'returns true when quantity is negative' do
      short_option = described_class.new('SPY250620P00450000', quantity: -3)
      expect(short_option.short?).to be true
    end

    it 'returns false when quantity is positive' do
      expect(put_option.short?).to be false
    end
  end

  describe '#long?' do
    it 'returns true when quantity is positive' do
      expect(put_option.long?).to be true
    end

    it 'returns false when quantity is negative' do
      short_option = described_class.new('SPY250620P00450000', quantity: -3)
      expect(short_option.long?).to be false
    end
  end

  describe 'inheritance' do
    it 'inherits from StrategyBase' do
      expect(put_option).to be_a(Platypi::StrategyBase)
    end

    it 'includes Quoteable module' do
      expect(described_class.included_modules).to include(Platypi::Quoteable)
    end
  end
end