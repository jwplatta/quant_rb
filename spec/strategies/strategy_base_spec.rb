# frozen_string_literal: true

require 'spec_helper'

RSpec.describe OptionsTrader::StrategyBase do
  let(:strategy) { described_class.new(increment: 0.05, round: 2) }

  describe '#initialize' do
    it 'sets default increment and round values' do
      default_strategy = described_class.new

      expect(default_strategy.increment).to eq(0.01)
      expect(default_strategy.round).to eq(2)
    end

    it 'accepts custom increment and round values' do
      expect(strategy.increment).to eq(0.05)
      expect(strategy.round).to eq(2)
    end
  end

  describe '#type' do
    it 'returns the class name in lowercase' do
      expect(strategy.type).to eq('strategybase')
    end
  end

  describe '#nearest_increment' do
    it 'rounds value to nearest increment' do
      expect(strategy.nearest_increment(1.23)).to eq(1.25)
      expect(strategy.nearest_increment(1.22)).to eq(1.20)
    end

    it 'handles negative values' do
      expect(strategy.nearest_increment(-1.23)).to eq(-1.25)
    end

    it 'rounds to specified decimal places' do
      strategy = described_class.new(increment: 0.01, round: 3)

      expect(strategy.nearest_increment(1.2345)).to eq(1.230)
    end
  end
end