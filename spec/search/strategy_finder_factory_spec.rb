# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Platypi::StrategyFinderFactory do
  describe '.create' do
    let(:underlying_symbol) { 'SPX' }
    let(:expiration_date) { '2025-07-04' }
    let(:quantity) { 2 }
    let(:settlement_type) { 'CASH' }
    let(:option_root) { 'SPXW' }

    let(:base_params) do
      {
        underlying_symbol: underlying_symbol,
        expiration_date: expiration_date,
        quantity: quantity,
        settlement_type: settlement_type,
        option_root: option_root
      }
    end

    context 'with valid strategy types' do
      it 'creates an IronCondorFinder for ironcondor strategy' do
        finder = described_class.create(strategy_type: 'ironcondor', **base_params)

        expect(finder).to be_a(Platypi::IronCondorFinder)
        expect(finder.underlying_symbol).to eq(underlying_symbol)
        expect(finder.expiration_date).to eq(expiration_date)
        expect(finder.quantity).to eq(quantity)
        expect(finder.settlement_type).to eq(settlement_type)
        expect(finder.option_root).to eq(option_root)
      end

      it 'creates a CallSpreadFinder for callspread strategy' do
        finder = described_class.create(strategy_type: 'callspread', **base_params)

        expect(finder).to be_a(Platypi::CallSpreadFinder)
        expect(finder.underlying_symbol).to eq(underlying_symbol)
        expect(finder.expiration_date).to eq(expiration_date)
        expect(finder.quantity).to eq(quantity)
        expect(finder.settlement_type).to eq(settlement_type)
        expect(finder.option_root).to eq(option_root)
      end

      it 'creates a PutSpreadFinder for putspread strategy' do
        finder = described_class.create(strategy_type: 'putspread', **base_params)

        expect(finder).to be_a(Platypi::PutSpreadFinder)
        expect(finder.underlying_symbol).to eq(underlying_symbol)
        expect(finder.expiration_date).to eq(expiration_date)
        expect(finder.quantity).to eq(quantity)
        expect(finder.settlement_type).to eq(settlement_type)
        expect(finder.option_root).to eq(option_root)
      end

      it 'handles case-insensitive strategy types' do
        expect(described_class.create(strategy_type: 'IRONCONDOR', **base_params)).to be_a(Platypi::IronCondorFinder)
        expect(described_class.create(strategy_type: 'CallSpread', **base_params)).to be_a(Platypi::CallSpreadFinder)
        expect(described_class.create(strategy_type: 'PutSpread', **base_params)).to be_a(Platypi::PutSpreadFinder)
      end

      it 'handles symbol strategy types' do
        expect(described_class.create(strategy_type: :ironcondor, **base_params)).to be_a(Platypi::IronCondorFinder)
        expect(described_class.create(strategy_type: :callspread, **base_params)).to be_a(Platypi::CallSpreadFinder)
        expect(described_class.create(strategy_type: :putspread, **base_params)).to be_a(Platypi::PutSpreadFinder)
      end
    end

    context 'with invalid strategy types' do
      it 'raises ArgumentError for unknown strategy type' do
        expect do
          described_class.create(strategy_type: 'unknown', **base_params)
        end.to raise_error(ArgumentError, 'Invalid strategy type: unknown. Valid types are: ironcondor, callspread, putspread')
      end

      it 'raises ArgumentError for similar but incorrect strategy names' do
        expect do
          described_class.create(strategy_type: 'iron_condor', **base_params)
        end.to raise_error(ArgumentError, 'Invalid strategy type: iron_condor. Valid types are: ironcondor, callspread, putspread')

        expect do
          described_class.create(strategy_type: 'call_spread', **base_params)
        end.to raise_error(ArgumentError, 'Invalid strategy type: call_spread. Valid types are: ironcondor, callspread, putspread')

        expect do
          described_class.create(strategy_type: 'put_spread', **base_params)
        end.to raise_error(ArgumentError, 'Invalid strategy type: put_spread. Valid types are: ironcondor, callspread, putspread')
      end

      it 'raises ArgumentError for empty string' do
        expect do
          described_class.create(strategy_type: '', **base_params)
        end.to raise_error(ArgumentError, 'Invalid strategy type: . Valid types are: ironcondor, callspread, putspread')
      end

      it 'raises ArgumentError for nil strategy type' do
        expect do
          described_class.create(strategy_type: nil, **base_params)
        end.to raise_error(ArgumentError, 'Invalid strategy type: . Valid types are: ironcondor, callspread, putspread')
      end
    end

    context 'with optional parameters' do
      it 'creates finder with default quantity when not specified' do
        params = base_params.except(:quantity)
        finder = described_class.create(strategy_type: 'ironcondor', **params)

        expect(finder.quantity).to eq(1)
      end

      it 'creates finder with nil optional parameters' do
        minimal_params = {
          strategy_type: 'ironcondor',
          underlying_symbol: underlying_symbol,
          expiration_date: expiration_date
        }

        finder = described_class.create(**minimal_params)

        expect(finder).to be_a(Platypi::IronCondorFinder)
        expect(finder.underlying_symbol).to eq(underlying_symbol)
        expect(finder.expiration_date).to eq(expiration_date)
        expect(finder.quantity).to eq(1)
        expect(finder.settlement_type).to be_nil
        expect(finder.option_root).to be_nil
      end
    end

    context 'with required parameters missing' do
      it 'requires underlying_symbol parameter' do
        params = base_params.except(:underlying_symbol)

        expect do
          described_class.create(strategy_type: 'ironcondor', **params)
        end.to raise_error(ArgumentError)
      end

      it 'requires expiration_date parameter' do
        params = base_params.except(:expiration_date)

        expect do
          described_class.create(strategy_type: 'ironcondor', **params)
        end.to raise_error(ArgumentError)
      end

      it 'requires strategy_type parameter' do
        expect do
          described_class.create(**base_params.except(:strategy_type))
        end.to raise_error(ArgumentError)
      end
    end
  end

  describe '.valid_strategy?' do
    it 'returns true for valid strategy types' do
      expect(described_class.valid_strategy?('ironcondor')).to be true
      expect(described_class.valid_strategy?('callspread')).to be true
      expect(described_class.valid_strategy?('putspread')).to be true
    end

    it 'handles case-insensitive validation' do
      expect(described_class.valid_strategy?('IRONCONDOR')).to be true
      expect(described_class.valid_strategy?('CallSpread')).to be true
      expect(described_class.valid_strategy?('PutSpread')).to be true
    end

    it 'handles symbol strategy types' do
      expect(described_class.valid_strategy?(:ironcondor)).to be true
      expect(described_class.valid_strategy?(:callspread)).to be true
      expect(described_class.valid_strategy?(:putspread)).to be true
    end

    it 'returns false for invalid strategy types' do
      expect(described_class.valid_strategy?('unknown')).to be false
      expect(described_class.valid_strategy?('iron_condor')).to be false
      expect(described_class.valid_strategy?('call_spread')).to be false
      expect(described_class.valid_strategy?('put_spread')).to be false
      expect(described_class.valid_strategy?('')).to be false
      expect(described_class.valid_strategy?(nil)).to be false
    end
  end

  describe 'VALID_STRATEGIES constant' do
    it 'contains exactly the expected strategy types' do
      expect(described_class::VALID_STRATEGIES).to eq(%w[ironcondor callspread putspread])
    end

    it 'is frozen' do
      expect(described_class::VALID_STRATEGIES).to be_frozen
    end
  end
end
