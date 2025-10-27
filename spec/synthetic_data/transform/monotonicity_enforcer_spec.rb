require 'spec_helper'

RSpec.describe OptionsTrader::SyntheticData::Transform::MonotonicityEnforcer do
  let(:underlying_price) { 5900.0 }
  let(:expiration_date) { Date.today + 1 }
  let(:timestamp) { Time.now }

  def create_option(strike:, mark:, contract_type:)
    OptionsTrader::DataObjects::Option.new(
      symbol: "SPX#{expiration_date.strftime('%y%m%d')}#{contract_type[0]}#{(strike * 1000).to_i}",
      underlying_symbol: 'SPX',
      strike: strike,
      put_call: contract_type,
      mark: mark,
      underlying_price: underlying_price,
      expiration_date: expiration_date,
      days_to_expiration: 1,
      timestamp: timestamp
    )
  end

  describe '.enforce with CALL options' do
    it 'removes violations where marks increase with strike' do
      # Calls should have decreasing marks as strikes increase
      # Input: [5800:120, 5850:75, 5900:28, 5950:35] - violation at 5950 (went back up)
      calls = [
        create_option(strike: 5800, mark: 120.0, contract_type: 'CALL'),
        create_option(strike: 5850, mark: 75.0, contract_type: 'CALL'),
        create_option(strike: 5900, mark: 28.0, contract_type: 'CALL'),
        create_option(strike: 5950, mark: 35.0, contract_type: 'CALL')
      ]

      result = described_class.enforce(calls, contract_type: 'CALL', method: 'remove')

      # The violating option should have nil mark
      expect(result.find { |c| c.strike == 5950 }.mark).to be_nil

      # Non-violating options should keep their marks
      expect(result.find { |c| c.strike == 5800 }.mark).to eq(120.0)
      expect(result.find { |c| c.strike == 5850 }.mark).to eq(75.0)
      expect(result.find { |c| c.strike == 5900 }.mark).to eq(28.0)
    end

    it 'handles monotonic calls (no violations)' do
      calls = [
        create_option(strike: 5800, mark: 120.0, contract_type: 'CALL'),
        create_option(strike: 5850, mark: 75.0, contract_type: 'CALL'),
        create_option(strike: 5900, mark: 28.0, contract_type: 'CALL'),
        create_option(strike: 5950, mark: 10.0, contract_type: 'CALL')
      ]

      result = described_class.enforce(calls, contract_type: 'CALL', method: 'remove')

      # All options should keep their marks
      result.each do |opt|
        expect(opt.mark).not_to be_nil
      end
    end

    it 'handles multiple violations' do
      calls = [
        create_option(strike: 5800, mark: 120.0, contract_type: 'CALL'),
        create_option(strike: 5850, mark: 75.0, contract_type: 'CALL'),
        create_option(strike: 5900, mark: 80.0, contract_type: 'CALL'),  # Violation 1
        create_option(strike: 5950, mark: 79.0, contract_type: 'CALL'),   # Violation 2
        create_option(strike: 5955, mark: 75.0, contract_type: 'CALL'),
        create_option(strike: 5960, mark: 74.0, contract_type: 'CALL'),
        create_option(strike: 5965, mark: 73.0, contract_type: 'CALL')
      ]

      result = described_class.enforce(calls, contract_type: 'CALL', method: 'remove')

      # Both violating options should have nil marks
      expect(result.find { |c| c.strike == 5900 }.mark).to be_nil
      expect(result.find { |c| c.strike == 5950 }.mark).to be_nil

      # Non-violating options should keep their marks
      expect(result.find { |c| c.strike == 5800 }.mark).to eq(120.0)
      expect(result.find { |c| c.strike == 5850 }.mark).to eq(75.0)
      expect(result.find { |c| c.strike == 5955 }.mark).to eq(75.0)
      expect(result.find { |c| c.strike == 5960 }.mark).to eq(74.0)
      expect(result.find { |c| c.strike == 5965 }.mark).to eq(73.0)
    end
  end

  describe '.enforce with PUT options' do
    it 'removes violations where marks decrease with strike' do
      # Puts should have increasing marks as strikes increase
      # Input: [5800:10, 5850:5, 5900:28, 5950:75] - violation at 5850 (went down)
      puts_opts = [
        create_option(strike: 5800, mark: 10.0, contract_type: 'PUT'),
        create_option(strike: 5850, mark: 5.0, contract_type: 'PUT'),   # Violation
        create_option(strike: 5900, mark: 28.0, contract_type: 'PUT'),
        create_option(strike: 5950, mark: 75.0, contract_type: 'PUT')
      ]

      result = described_class.enforce(puts_opts, contract_type: 'PUT', method: 'remove')

      # The violating option should have nil mark
      expect(result.find { |p| p.strike == 5850 }.mark).to be_nil

      # Non-violating options should keep their marks
      expect(result.find { |p| p.strike == 5800 }.mark).to eq(10.0)
      expect(result.find { |p| p.strike == 5900 }.mark).to eq(28.0)
      expect(result.find { |p| p.strike == 5950 }.mark).to eq(75.0)
    end

    it 'handles monotonic puts (no violations)' do
      puts_opts = [
        create_option(strike: 5800, mark: 10.0, contract_type: 'PUT'),
        create_option(strike: 5850, mark: 20.0, contract_type: 'PUT'),
        create_option(strike: 5900, mark: 28.0, contract_type: 'PUT'),
        create_option(strike: 5950, mark: 75.0, contract_type: 'PUT')
      ]

      result = described_class.enforce(puts_opts, contract_type: 'PUT', method: 'remove')

      result.each do |opt|
        expect(opt.mark).not_to be_nil
      end
    end

    it 'handles multiple violations' do
      puts_opts = [
        create_option(strike: 5800, mark: 50.0, contract_type: 'PUT'),
        create_option(strike: 5850, mark: 40.0, contract_type: 'PUT'),  # Violation 1
        create_option(strike: 5900, mark: 30.0, contract_type: 'PUT'),  # Violation 2
        create_option(strike: 5925, mark: 50.0, contract_type: 'PUT'),
        create_option(strike: 5950, mark: 75.0, contract_type: 'PUT'),
        create_option(strike: 6000, mark: 80.0, contract_type: 'PUT')
      ]

      result = described_class.enforce(puts_opts, contract_type: 'PUT', method: 'remove')

      expect(result.find { |p| p.strike == 5850 }.mark).to be_nil
      expect(result.find { |p| p.strike == 5900 }.mark).to be_nil

      expect(result.find { |p| p.strike == 5800 }.mark).to eq(50.0)
      expect(result.find { |p| p.strike == 5925 }.mark).to eq(50.0)
      expect(result.find { |p| p.strike == 5950 }.mark).to eq(75.0)
      expect(result.find { |p| p.strike == 6000 }.mark).to eq(80.0)
    end
  end

  describe 'edge cases' do
    it 'handles empty array' do
      result = described_class.enforce([], contract_type: 'CALL', method: 'remove')
      expect(result).to eq([])
    end

    it 'handles single option' do
      calls = [create_option(strike: 5900, mark: 28.0, contract_type: 'CALL')]
      result = described_class.enforce(calls, contract_type: 'CALL', method: 'remove')

      expect(result.length).to eq(1)
      expect(result.first.mark).to eq(28.0)
    end

    it 'handles options with nil marks' do
      calls = [
        create_option(strike: 5800, mark: 120.0, contract_type: 'CALL'),
        create_option(strike: 5850, mark: nil, contract_type: 'CALL'),
        create_option(strike: 5900, mark: 28.0, contract_type: 'CALL')
      ]

      result = described_class.enforce(calls, contract_type: 'CALL', method: 'remove')

      expect(result.find { |c| c.strike == 5800 }.mark).to eq(120.0)
      expect(result.find { |c| c.strike == 5850 }.mark).to be_nil
      expect(result.find { |c| c.strike == 5900 }.mark).to eq(28.0)
    end

    it 'handles unsorted input' do
      calls = [
        create_option(strike: 5950, mark: 10.0, contract_type: 'CALL'),
        create_option(strike: 5800, mark: 120.0, contract_type: 'CALL'),
        create_option(strike: 5900, mark: 28.0, contract_type: 'CALL'),
        create_option(strike: 5850, mark: 75.0, contract_type: 'CALL')
      ]

      result = described_class.enforce(calls, contract_type: 'CALL', method: 'remove')

      expect(result.find { |c| c.strike == 5800 }.mark).to eq(120.0)
      expect(result.find { |c| c.strike == 5850 }.mark).to eq(75.0)
      expect(result.find { |c| c.strike == 5900 }.mark).to eq(28.0)
      expect(result.find { |c| c.strike == 5950 }.mark).to eq(10.0)
    end
  end

  describe 'does not modify original options' do
    it 'returns cloned options' do
      calls = [
        create_option(strike: 5900, mark: 28.0, contract_type: 'CALL'),
        create_option(strike: 5950, mark: 35.0, contract_type: 'CALL')  # Violation
      ]

      original_marks = calls.map(&:mark)
      result = described_class.enforce(calls, contract_type: 'CALL', method: 'remove')

      expect(calls.map(&:mark)).to eq(original_marks)
      expect(result.find { |c| c.strike == 5950 }.mark).to be_nil
    end
  end
end
