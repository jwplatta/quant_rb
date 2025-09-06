# frozen_string_literal: true

require 'spec_helper'

RSpec.describe OptionsTrader::StrategySearchFactory do
  describe '.create' do
    let(:underlying_symbol) { 'SPX' }
    let(:expiration_date) { '2025-07-04' }
    let(:quantity) { 2 }
    let(:settlement_type) { 'CASH' }
    let(:option_root) { 'SPXW' }
    let(:mock_markets_service) { double('OptionsTrader::Services::Markets') }

    let(:base_params) do
      {
        markets_service: mock_markets_service,
        underlying_symbol: underlying_symbol,
        expiration_date: expiration_date,
        quantity: quantity,
        settlement_type: settlement_type,
        option_root: option_root
      }
    end

    context 'with valid strategy types' do
      it 'creates an IronCondorSearch for ironcondor strategy' do
        finder = described_class.create(strategy_type: 'ironcondor', **base_params)

        expect(finder).to be_a(OptionsTrader::IronCondorSearch)
        expect(finder.underlying_symbol).to eq(underlying_symbol)
        expect(finder.expiration_date).to eq(expiration_date)
        expect(finder.quantity).to eq(quantity)
        expect(finder.settlement_type).to eq(settlement_type)
        expect(finder.option_root).to eq(option_root)
      end

      it 'creates a VerticalSpreadSearch for callspread strategy' do
        finder = described_class.create(strategy_type: 'vertical', put_call: 'CALL', **base_params)

        expect(finder).to be_a(OptionsTrader::VerticalSpreadSearch)
        expect(finder.underlying_symbol).to eq(underlying_symbol)
        expect(finder.expiration_date).to eq(expiration_date)
        expect(finder.quantity).to eq(quantity)
        expect(finder.settlement_type).to eq(settlement_type)
        expect(finder.option_root).to eq(option_root)
      end

      it 'creates a VerticalSpreadSearch for putspread strategy' do
        finder = described_class.create(strategy_type: 'vertical', put_call: 'PUT', **base_params)

        expect(finder).to be_a(OptionsTrader::VerticalSpreadSearch)
        expect(finder.underlying_symbol).to eq(underlying_symbol)
        expect(finder.expiration_date).to eq(expiration_date)
        expect(finder.quantity).to eq(quantity)
        expect(finder.settlement_type).to eq(settlement_type)
        expect(finder.option_root).to eq(option_root)
      end

      it 'handles case-insensitive strategy types' do
        expect(described_class.create(strategy_type: 'IRONCONDOR', **base_params)).to be_a(OptionsTrader::IronCondorSearch)
        expect(described_class.create(strategy_type: 'Vertical', **base_params)).to be_a(OptionsTrader::VerticalSpreadSearch)
      end

      it 'handles symbol strategy types' do
        expect(described_class.create(strategy_type: :ironcondor, **base_params)).to be_a(OptionsTrader::IronCondorSearch)
        expect(described_class.create(strategy_type: :vertical, **base_params)).to be_a(OptionsTrader::VerticalSpreadSearch)
      end
    end

    context 'with invalid strategy types' do
      it 'raises ArgumentError for unknown strategy type' do
        expect do
          described_class.create(strategy_type: 'unknown', **base_params)
        end.to raise_error(ArgumentError, 'Invalid strategy type: unknown. Valid types are: ironcondor, vertical, single')
      end

      it 'raises ArgumentError for similar but incorrect strategy names' do
        expect do
          described_class.create(strategy_type: 'iron_condor', **base_params)
        end.to raise_error(ArgumentError, 'Invalid strategy type: iron_condor. Valid types are: ironcondor, vertical, single')

        expect do
          described_class.create(strategy_type: 'call_spread', **base_params)
        end.to raise_error(ArgumentError, 'Invalid strategy type: call_spread. Valid types are: ironcondor, vertical, single')

        expect do
          described_class.create(strategy_type: 'put_spread', **base_params)
        end.to raise_error(ArgumentError, 'Invalid strategy type: put_spread. Valid types are: ironcondor, vertical, single')
      end

      it 'raises ArgumentError for empty string' do
        expect do
          described_class.create(strategy_type: '', **base_params)
        end.to raise_error(ArgumentError, 'Invalid strategy type: . Valid types are: ironcondor, vertical, single')
      end

      it 'raises ArgumentError for nil strategy type' do
        expect do
          described_class.create(strategy_type: nil, **base_params)
        end.to raise_error(ArgumentError, 'Invalid strategy type: . Valid types are: ironcondor, vertical, single')
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
          markets_service: mock_markets_service,
          strategy_type: 'ironcondor',
          underlying_symbol: underlying_symbol,
          expiration_date: expiration_date,
          option_root: option_root
        }

        finder = described_class.create(**minimal_params)

        expect(finder).to be_a(OptionsTrader::IronCondorSearch)
        expect(finder.underlying_symbol).to eq(underlying_symbol)
        expect(finder.expiration_date).to eq(expiration_date)
        expect(finder.quantity).to eq(1)
        expect(finder.settlement_type).to be_nil
        expect(finder.option_root).to eq(option_root)
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
      expect(described_class.valid_strategy?('vertical')).to be true
      expect(described_class.valid_strategy?('single')).to be true
    end

    it 'handles case-insensitive validation' do
      expect(described_class.valid_strategy?('IRONCONDOR')).to be true
      expect(described_class.valid_strategy?('Vertical')).to be true
    end

    it 'handles symbol strategy types' do
      expect(described_class.valid_strategy?(:ironcondor)).to be true
      expect(described_class.valid_strategy?(:vertical)).to be true
      expect(described_class.valid_strategy?(:single)).to be true
    end

    it 'returns false for invalid strategy types' do
      expect(described_class.valid_strategy?('unknown')).to be false
      expect(described_class.valid_strategy?('iron_condor')).to be false
      expect(described_class.valid_strategy?('vertical_spread')).to be false
      expect(described_class.valid_strategy?('single_option')).to be false
      expect(described_class.valid_strategy?('')).to be false
      expect(described_class.valid_strategy?(nil)).to be false
    end
  end

end
