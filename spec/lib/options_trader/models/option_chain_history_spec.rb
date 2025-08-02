require 'spec_helper'

RSpec.describe OptionsTrader::OptionChainHistory do
  describe 'validations' do
    it 'validates presence of required fields' do
      record = described_class.new
      expect(record).not_to be_valid
      expect(record.errors[:symbol]).to include("can't be blank")
      expect(record.errors[:underlying_symbol]).to include("can't be blank")
      expect(record.errors[:contract_type]).to include("can't be blank")
    end

    it 'validates contract_type inclusion' do
      record = described_class.new(contract_type: 'invalid')
      record.valid?
      expect(record.errors[:contract_type]).to include('is not included in the list')
    end

    it 'validates positive strike price' do
      record = described_class.new(strike: -10)
      record.valid?
      expect(record.errors[:strike]).to include('must be greater than 0')
    end
  end

  describe 'scopes' do
    let!(:call_option) { create_option_record(contract_type: 'CALL') }
    let!(:put_option) { create_option_record(contract_type: 'PUT') }

    describe '.calls' do
      it 'returns only call options' do
        expect(described_class.calls).to include(call_option)
        expect(described_class.calls).not_to include(put_option)
      end
    end

    describe '.puts' do
      it 'returns only put options' do
        expect(described_class.puts).to include(put_option)
        expect(described_class.puts).not_to include(call_option)
      end
    end
  end

  describe '#mid_price' do
    it 'calculates midpoint when bid and ask are present' do
      record = described_class.new(bid: 1.0, ask: 3.0)
      expect(record.mid_price).to eq(2.0)
    end

    it 'returns nil when bid is missing' do
      record = described_class.new(ask: 3.0)
      expect(record.mid_price).to be_nil
    end

    it 'returns nil when ask is missing' do
      record = described_class.new(bid: 1.0)
      expect(record.mid_price).to be_nil
    end
  end

  describe '#spread' do
    it 'calculates spread when bid and ask are present' do
      record = described_class.new(bid: 1.0, ask: 3.0)
      expect(record.spread).to eq(2.0)
    end

    it 'returns nil when bid or ask is missing' do
      record = described_class.new(bid: 1.0)
      expect(record.spread).to be_nil
    end
  end

  private

  def create_option_record(attributes = {})
    defaults = {
      symbol: 'AAPL250117C00150000',
      underlying_symbol: 'AAPL',
      contract_type: 'CALL',
      strike: 150.0,
      expiration_date: Date.current + 30.days,
      bid: 1.0,
      ask: 1.5,
      underlying_price: 145.0
    }
    described_class.create!(defaults.merge(attributes))
  end
end