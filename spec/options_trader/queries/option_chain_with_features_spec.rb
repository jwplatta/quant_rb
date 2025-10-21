require 'spec_helper'

RSpec.describe OptionsTrader::Queries::OptionChainWithFeatures do
  describe '.build_sql' do
    let(:underlying_symbol) { '$SPX' }
    let(:expiration_date) { '2025-06-13' }
    let(:end_time) { '2025-06-10 14:20:00' }
    let(:start_time) { '2025-06-10 14:00:00' }
    let(:contract_type) { 'PUT' }
    let(:source) { 'polygon' }

    # Mock connection.quote to avoid DB connection requirement
    let(:mock_connection) { double('connection') }

    before do
      allow(ActiveRecord::Base).to receive(:connection).and_return(mock_connection)
      allow(mock_connection).to receive(:quote) { |val| "'#{val}'" }
    end

    context 'without additional features' do
      it 'generates valid SQL' do
        sql = described_class.build_sql(
          underlying_symbol: underlying_symbol,
          expiration_date: expiration_date,
          end_time: end_time,
          start_time: start_time,
          contract_type: contract_type,
          features: [],
          source: source
        )

        expect(sql).to include('WITH options AS')
        expect(sql).to include('SELECT DISTINCT ON (symbol)')
        expect(sql).to include('FROM option_chain_history')
      end
    end

    context 'with VIX features' do
      it 'includes VIX9D, VVIX, and SKEW in query' do
        features = { vix9d: '$VIX9D', vvix: '$VVIX', skew: '$SKEW' }

        sql = described_class.build_sql(
          underlying_symbol: underlying_symbol,
          expiration_date: expiration_date,
          end_time: end_time,
          start_time: start_time,
          contract_type: contract_type,
          features: features,
          source: source
        )

        expect(sql).to include('vix9d.close as vix9d')
        expect(sql).to include('vvix.close as vvix')
        expect(sql).to include('skew.close as skew')
        expect(sql).to include("WHERE symbol = '$VIX9D'")
        expect(sql).to include("WHERE symbol = '$VVIX'")
        expect(sql).to include("WHERE symbol = '$SKEW'")
      end
    end

    context 'with CALL contract type' do
      it 'uses correct moneyness calculation for CALLs' do
        sql = described_class.build_sql(
          underlying_symbol: underlying_symbol,
          expiration_date: expiration_date,
          end_time: end_time,
          start_time: start_time,
          contract_type: 'CALL',
          features: [],
          source: source
        )

        expect(sql).to include('underlying.close::float / options.strike')
      end
    end

    context 'with PUT contract type' do
      it 'uses correct moneyness calculation for PUTs' do
        sql = described_class.build_sql(
          underlying_symbol: underlying_symbol,
          expiration_date: expiration_date,
          end_time: end_time,
          start_time: start_time,
          contract_type: 'PUT',
          features: [],
          source: source
        )

        expect(sql).to include('options.strike / underlying.close::float')
      end
    end
  end

  describe '.moneyness_select' do
    it 'returns correct expression for PUTs' do
      expect(described_class.send(:moneyness_select, 'PUT'))
        .to eq('options.strike / underlying.close::float')
    end

    it 'returns correct expression for CALLs' do
      expect(described_class.send(:moneyness_select, 'CALL'))
        .to eq('underlying.close::float / options.strike')
    end

    it 'raises error for invalid contract type' do
      expect { described_class.send(:moneyness_select, 'INVALID') }
        .to raise_error(ArgumentError, /Invalid contract_type/)
    end
  end

  describe '.moneyness_where' do
    it 'includes moneyness threshold for PUTs' do
      expect(described_class.send(:moneyness_where, 'PUT'))
        .to eq('options.strike / underlying.close::float <= 1.01')
    end

    it 'includes moneyness threshold for CALLs' do
      expect(described_class.send(:moneyness_where, 'CALL'))
        .to eq('underlying.close::float / options.strike <= 1.01')
    end
  end

  describe '.feature_selects' do
    it 'returns empty string for no features' do
      expect(described_class.send(:feature_selects, {})).to eq('')
    end

    it 'returns SELECT clauses for features' do
      result = described_class.send(:feature_selects, { vix9d: '$VIX9D', vvix: '$VVIX' })
      expect(result).to include('vix9d.close as vix9d')
      expect(result).to include('vvix.close as vvix')
    end
  end

  describe '.feature_joins' do
    it 'returns empty string for no features' do
      expect(described_class.send(:feature_joins, {})).to eq('')
    end

    it 'returns LATERAL JOIN clauses for features' do
      result = described_class.send(:feature_joins, { vix9d: '$VIX9D' })
      expect(result).to include('LEFT JOIN LATERAL')
      expect(result).to include("WHERE symbol = '$VIX9D'")
    end
  end

  describe '.sanitize_symbol' do
    it 'allows valid symbols with $ prefix' do
      expect(described_class.send(:sanitize_symbol, '$SPX')).to eq('$SPX')
    end

    it 'allows valid symbols without $ prefix' do
      expect(described_class.send(:sanitize_symbol, 'SPX')).to eq('SPX')
    end

    it 'allows alphanumeric symbols' do
      expect(described_class.send(:sanitize_symbol, 'SPX500')).to eq('SPX500')
    end

    it 'raises error for symbols with special characters' do
      expect { described_class.send(:sanitize_symbol, '$SPX; DROP TABLE') }
        .to raise_error(ArgumentError, /Invalid symbol/)
    end

    it 'raises error for symbols with spaces' do
      expect { described_class.send(:sanitize_symbol, '$SPX 500') }
        .to raise_error(ArgumentError, /Invalid symbol/)
    end
  end

  describe '.calculate_start_time' do
    it 'calculates start time from string end_time' do
      end_time = '2025-06-10 14:20:00'
      window_minutes = 20
      result = described_class.send(:calculate_start_time, end_time, window_minutes)
      expect(result).to eq('2025-06-10 14:00:00')
    end

    it 'calculates start time from Time object' do
      end_time = Time.parse('2025-06-10 14:20:00')
      window_minutes = 20
      result = described_class.send(:calculate_start_time, end_time, window_minutes)
      expect(result).to eq('2025-06-10 14:00:00')
    end
  end
end
