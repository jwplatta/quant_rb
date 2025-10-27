require 'spec_helper'

RSpec.describe OptionsTrader::SyntheticData::Transform::MonotonicityEnforcer do
  let(:underlying_price) { 5900.0 }
  let(:expiration_date) { Date.today + 1 }
  let(:timestamp) { Time.now }

  def create_option(strike:, mark:, contract_type:, open: nil, high: nil, low: nil, close: nil)
    OptionsTrader::DataObjects::Option.new(
      symbol: "SPX#{expiration_date.strftime('%y%m%d')}#{contract_type[0]}#{(strike * 1000).to_i}",
      underlying_symbol: 'SPX',
      strike: strike,
      put_call: contract_type,
      mark: mark,
      underlying_price: underlying_price,
      expiration_date: expiration_date,
      days_to_expiration: 1,
      timestamp: timestamp,
      open: open,
      high: high,
      low: low,
      close: close
    )
  end

  describe '.enforce for CALL options' do
    it 'fixes simple monotonicity violation using midpoint' do
      options = [
        create_option(strike: 5800, mark: 120.0, contract_type: 'CALL'),
        create_option(strike: 5850, mark: 90.0, contract_type: 'CALL'),
        create_option(strike: 5900, mark: 95.0, contract_type: 'CALL'), # violation
        create_option(strike: 5950, mark: 40.0, contract_type: 'CALL')
      ]

      result = described_class.enforce(options, contract_type: 'CALL')

      # Verify monotonicity: each price should be greater than the next
      (0...result.length - 1).each do |i|
        expect(result[i].mark).to be > result[i + 1].mark
      end
    end

    it 'uses alternative prices when available' do
      options = [
        create_option(strike: 5800, mark: 120.0, contract_type: 'CALL'),
        create_option(strike: 5850, mark: 95.0, contract_type: 'CALL', open: 80.0, high: 100.0, low: 75.0), # violation, but has valid alternative
        create_option(strike: 5900, mark: 60.0, contract_type: 'CALL')
      ]

      result = described_class.enforce(options, contract_type: 'CALL')

      expect(result[1].mark).to be_between(60.0, 120.0)
    end

    it 'handles multiple violations iteratively' do
      options = [
        create_option(strike: 5800, mark: 100.0, contract_type: 'CALL'),
        create_option(strike: 5850, mark: 110.0, contract_type: 'CALL'), # violation
        create_option(strike: 5900, mark: 105.0, contract_type: 'CALL'), # violation
        create_option(strike: 5950, mark: 50.0, contract_type: 'CALL')
      ]

      result = described_class.enforce(options, contract_type: 'CALL')

      (0...result.length - 1).each do |i|
        expect(result[i].mark).to be > result[i + 1].mark
      end
    end
  end

  describe '.enforce for PUT options' do
    it 'fixes simple monotonicity violation using midpoint' do
      options = [
        create_option(strike: 5800, mark: 40.0, contract_type: 'PUT'),
        create_option(strike: 5850, mark: 60.0, contract_type: 'PUT'),
        create_option(strike: 5900, mark: 55.0, contract_type: 'PUT'), # violation
        create_option(strike: 5950, mark: 120.0, contract_type: 'PUT')
      ]

      result = described_class.enforce(options, contract_type: 'PUT')

      (0...result.length - 1).each do |i|
        expect(result[i].mark).to be < result[i + 1].mark
      end
    end

    it 'handles multiple violations iteratively' do
      options = [
        create_option(strike: 5800, mark: 100.0, contract_type: 'PUT'),
        create_option(strike: 5850, mark: 90.0, contract_type: 'PUT'), # violation
        create_option(strike: 5900, mark: 95.0, contract_type: 'PUT'), # violation
        create_option(strike: 5950, mark: 150.0, contract_type: 'PUT')
      ]

      result = described_class.enforce(options, contract_type: 'PUT')

      # Verify monotonicity: each price should be less than the next
      (0...result.length - 1).each do |i|
        expect(result[i].mark).to be < result[i + 1].mark
      end
    end
  end

  describe 'OHLC averaging strategy' do
    it 'uses OHLC average when it satisfies monotonicity' do
      options = [
        create_option(strike: 5800, mark: 120.0, contract_type: 'CALL'),
        create_option(strike: 5850, mark: 100.0, contract_type: 'CALL',
                     open: 85.0, high: 90.0, low: 80.0, close: 87.0), # avg = 88.4
        create_option(strike: 5900, mark: 60.0, contract_type: 'CALL')
      ]

      result = described_class.enforce(options, contract_type: 'CALL')

      # The OHLC average should be used if it creates valid monotonicity
      expect(result[1].mark).to be_between(60.0, 120.0)
    end
  end

  describe 'method: remove' do
    describe 'for CALL options' do
      it 'removes violations by setting mark to nil from ATM towards OTM (higher strikes)' do
        # ATM is around 5900
        # OTM direction: 5900 -> 5950 -> 6000 (prices should decrease)
        options = [
          create_option(strike: 5850, mark: 80.0, contract_type: 'CALL'), # ITM
          create_option(strike: 5900, mark: 60.0, contract_type: 'CALL'), # ATM
          create_option(strike: 5950, mark: 40.0, contract_type: 'CALL'), # OTM
          create_option(strike: 6000, mark: 50.0, contract_type: 'CALL')  # OTM - violation! (increased)
        ]

        result = described_class.enforce(options, contract_type: 'CALL', method: 'remove')

        expect(result[0].mark).to eq(80.0)
        expect(result[1].mark).to eq(60.0)
        expect(result[2].mark).to eq(40.0)
        expect(result[3].mark).to be_nil # violation removed
      end

      it 'removes violations by setting mark to nil from ATM towards ITM (lower strikes)' do
        # ATM is around 5900
        # ITM direction: 5900 -> 5850 -> 5800 (prices should increase)
        options = [
          create_option(strike: 5800, mark: 90.0, contract_type: 'CALL'),  # ITM - violation! (decreased)
          create_option(strike: 5850, mark: 100.0, contract_type: 'CALL'), # ITM
          create_option(strike: 5900, mark: 60.0, contract_type: 'CALL'),  # ATM
          create_option(strike: 5950, mark: 40.0, contract_type: 'CALL')   # OTM
        ]

        result = described_class.enforce(options, contract_type: 'CALL', method: 'remove')

        expect(result[0].mark).to be_nil # violation removed
        expect(result[1].mark).to eq(100.0)
        expect(result[2].mark).to eq(60.0)
        expect(result[3].mark).to eq(40.0)
      end

      it 'handles multiple violations in both directions' do
        options = [
          create_option(strike: 5800, mark: 95.0, contract_type: 'CALL'),  # ITM - violation
          create_option(strike: 5850, mark: 100.0, contract_type: 'CALL'), # ITM
          create_option(strike: 5900, mark: 60.0, contract_type: 'CALL'),  # ATM
          create_option(strike: 5950, mark: 40.0, contract_type: 'CALL'),  # OTM
          create_option(strike: 6000, mark: 45.0, contract_type: 'CALL')   # OTM - violation
        ]

        result = described_class.enforce(options, contract_type: 'CALL', method: 'remove')

        expect(result[0].mark).to be_nil # ITM violation
        expect(result[1].mark).to eq(100.0)
        expect(result[2].mark).to eq(60.0)
        expect(result[3].mark).to eq(40.0)
        expect(result[4].mark).to be_nil # OTM violation
      end
    end

    describe 'for PUT options' do
      it 'removes violations by setting mark to nil from ATM towards OTM (lower strikes)' do
        # ATM is around 5900
        # OTM direction: 5900 -> 5850 -> 5800 (prices should decrease)
        options = [
          create_option(strike: 5800, mark: 35.0, contract_type: 'PUT'),  # OTM - violation! (increased)
          create_option(strike: 5850, mark: 30.0, contract_type: 'PUT'),  # OTM
          create_option(strike: 5900, mark: 60.0, contract_type: 'PUT'),  # ATM
          create_option(strike: 5950, mark: 80.0, contract_type: 'PUT')   # ITM
        ]

        result = described_class.enforce(options, contract_type: 'PUT', method: 'remove')

        expect(result[0].mark).to be_nil # violation removed
        expect(result[1].mark).to eq(30.0)
        expect(result[2].mark).to eq(60.0)
        expect(result[3].mark).to eq(80.0)
      end

      it 'removes violations by setting mark to nil from ATM towards ITM (higher strikes)' do
        # ATM is around 5900
        # ITM direction: 5900 -> 5950 -> 6000 (prices should increase)
        options = [
          create_option(strike: 5850, mark: 30.0, contract_type: 'PUT'),  # OTM
          create_option(strike: 5900, mark: 60.0, contract_type: 'PUT'),  # ATM
          create_option(strike: 5950, mark: 80.0, contract_type: 'PUT'),  # ITM
          create_option(strike: 6000, mark: 75.0, contract_type: 'PUT')   # ITM - violation! (decreased)
        ]

        result = described_class.enforce(options, contract_type: 'PUT', method: 'remove')

        expect(result[0].mark).to eq(30.0)
        expect(result[1].mark).to eq(60.0)
        expect(result[2].mark).to eq(80.0)
        expect(result[3].mark).to be_nil # violation removed
      end

      it 'handles multiple violations in both directions' do
        options = [
          create_option(strike: 5800, mark: 35.0, contract_type: 'PUT'),  # OTM - violation
          create_option(strike: 5850, mark: 30.0, contract_type: 'PUT'),  # OTM
          create_option(strike: 5900, mark: 60.0, contract_type: 'PUT'),  # ATM
          create_option(strike: 5950, mark: 80.0, contract_type: 'PUT'),  # ITM
          create_option(strike: 6000, mark: 75.0, contract_type: 'PUT')   # ITM - violation
        ]

        result = described_class.enforce(options, contract_type: 'PUT', method: 'remove')

        expect(result[0].mark).to be_nil # OTM violation
        expect(result[1].mark).to eq(30.0)
        expect(result[2].mark).to eq(60.0)
        expect(result[3].mark).to eq(80.0)
        expect(result[4].mark).to be_nil # ITM violation
      end
    end

    describe 'error handling' do
      it 'raises MissingUnderlyingPriceError when underlying_price is not set' do
        option_without_price = double('Option', strike: 5900, mark: 60.0, underlying_price: nil)
        allow(option_without_price).to receive(:respond_to?).with(:underlying_price).and_return(true)

        options = [option_without_price]

        expect {
          described_class.enforce(options, contract_type: 'CALL', method: 'remove')
        }.to raise_error(OptionsTrader::SyntheticData::Transform::MonotonicityEnforcer::MissingUnderlyingPriceError)
      end

      it 'raises ArgumentError for invalid method parameter' do
        options = [create_option(strike: 5900, mark: 60.0, contract_type: 'CALL')]

        expect {
          described_class.enforce(options, contract_type: 'CALL', method: 'invalid')
        }.to raise_error(ArgumentError, /Invalid method/)
      end
    end

    describe 'ATM strike detection' do
      it 'correctly identifies ATM strike when underlying price is between strikes' do
        # underlying_price = 5900, so ATM should be 5900
        options = [
          create_option(strike: 5850, mark: 100.0, contract_type: 'CALL'),
          create_option(strike: 5900, mark: 60.0, contract_type: 'CALL'),  # ATM
          create_option(strike: 5950, mark: 40.0, contract_type: 'CALL')
        ]

        result = described_class.enforce(options, contract_type: 'CALL', method: 'remove')

        # No violations, all marks should remain
        expect(result.all? { |o| o.mark }).to be true
      end

      it 'correctly identifies ATM strike when underlying price is exactly at a strike' do
        # underlying_price = 5900
        options = [
          create_option(strike: 5850, mark: 100.0, contract_type: 'CALL'),
          create_option(strike: 5900, mark: 60.0, contract_type: 'CALL'),  # ATM (exact match)
          create_option(strike: 5950, mark: 40.0, contract_type: 'CALL')
        ]

        result = described_class.enforce(options, contract_type: 'CALL', method: 'remove')

        expect(result.all? { |o| o.mark }).to be true
      end
    end
  end

  describe 'backward compatibility' do
    it 'uses adjust method by default when method parameter is not specified' do
      options = [
        create_option(strike: 5800, mark: 120.0, contract_type: 'CALL'),
        create_option(strike: 5850, mark: 90.0, contract_type: 'CALL'),
        create_option(strike: 5900, mark: 95.0, contract_type: 'CALL'), # violation
        create_option(strike: 5950, mark: 40.0, contract_type: 'CALL')
      ]

      result = described_class.enforce(options, contract_type: 'CALL')

      # All marks should still be set (adjusted, not removed)
      expect(result.all? { |o| o.mark }).to be true

      # Verify monotonicity
      (0...result.length - 1).each do |i|
        expect(result[i].mark).to be > result[i + 1].mark
      end
    end
  end
end
