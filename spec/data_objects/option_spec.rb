require 'spec_helper'
require 'options_trader/data_objects/option'

RSpec.describe OptionsTrader::DataObjects::Option do
  describe '#in_the_money?' do
    context 'for call options' do
      it 'returns true when underlying price is above strike' do
        option = described_class.new(
          symbol: 'SPXW241025C5800',
          underlying_symbol: 'SPX',
          strike: 5800,
          put_call: 'CALL',
          mark: 10.0,
          underlying_price: 5850,
          expiration_date: '2024-10-25'
        )

        expect(option.in_the_money?).to be true
      end

      it 'returns false when underlying price is below strike' do
        option = described_class.new(
          symbol: 'SPXW241025C5800',
          underlying_symbol: 'SPX',
          strike: 5800,
          put_call: 'CALL',
          mark: 10.0,
          underlying_price: 5750,
          expiration_date: '2024-10-25'
        )

        expect(option.in_the_money?).to be false
      end

      it 'returns false when underlying price is nil' do
        option = described_class.new(
          symbol: 'SPXW241025C5800',
          underlying_symbol: 'SPX',
          strike: 5800,
          put_call: 'CALL',
          mark: 10.0,
          underlying_price: nil,
          expiration_date: '2024-10-25'
        )

        expect(option.in_the_money?).to be false
      end
    end

    context 'for put options' do
      it 'returns true when underlying price is below strike' do
        option = described_class.new(
          symbol: 'SPXW241025P5800',
          underlying_symbol: 'SPX',
          strike: 5800,
          put_call: 'PUT',
          mark: 10.0,
          underlying_price: 5750,
          expiration_date: '2024-10-25'
        )

        expect(option.in_the_money?).to be true
      end

      it 'returns false when underlying price is above strike' do
        option = described_class.new(
          symbol: 'SPXW241025P5800',
          underlying_symbol: 'SPX',
          strike: 5800,
          put_call: 'PUT',
          mark: 10.0,
          underlying_price: 5850,
          expiration_date: '2024-10-25'
        )

        expect(option.in_the_money?).to be false
      end
    end
  end

  describe '#intrinsic' do
    context 'for OTM options' do
      it 'returns 0.0 for OTM call' do
        option = described_class.new(
          symbol: 'SPXW241025C5800',
          underlying_symbol: 'SPX',
          strike: 5800,
          put_call: 'CALL',
          mark: 10.0,
          underlying_price: 5750,
          expiration_date: '2024-10-25'
        )

        expect(option.intrinsic).to eq(0.0)
      end

      it 'returns 0.0 for OTM put' do
        option = described_class.new(
          symbol: 'SPXW241025P5800',
          underlying_symbol: 'SPX',
          strike: 5800,
          put_call: 'PUT',
          mark: 8.0,
          underlying_price: 5850,
          expiration_date: '2024-10-25'
        )

        expect(option.intrinsic).to eq(0.0)
      end
    end

    context 'for ITM options' do
      it 'calculates intrinsic for ITM call' do
        # Underlying: 5850, Strike: 5800
        # Intrinsic: 5850 - 5800 = 50
        # Mark: 60
        # Extrinsic: 60 - 50 = 10
        # Intrinsic = Mark - Extrinsic = 60 - 10 = 50
        option = described_class.new(
          symbol: 'SPXW241025C5800',
          underlying_symbol: 'SPX',
          strike: 5800,
          put_call: 'CALL',
          mark: 60.0,
          underlying_price: 5850,
          expiration_date: '2024-10-25'
        )

        expect(option.intrinsic).to eq(50.0)
      end

      it 'calculates intrinsic for ITM put' do
        # Underlying: 5750, Strike: 5800
        # Intrinsic: 5800 - 5750 = 50
        # Mark: 55
        # Extrinsic: 55 - 50 = 5
        # Intrinsic = Mark - Extrinsic = 55 - 5 = 50
        option = described_class.new(
          symbol: 'SPXW241025P5800',
          underlying_symbol: 'SPX',
          strike: 5800,
          put_call: 'PUT',
          mark: 55.0,
          underlying_price: 5750,
          expiration_date: '2024-10-25'
        )

        expect(option.intrinsic).to eq(50.0)
      end

      it 'raises error when underlying_price is nil for ITM option' do
        option = described_class.new(
          symbol: 'SPXW241025C5800',
          underlying_symbol: 'SPX',
          strike: 5800,
          put_call: 'CALL',
          mark: 60.0,
          underlying_price: nil,
          expiration_date: '2024-10-25'
        )

        # Manually set in_the_money to trigger the error path
        allow(option).to receive(:in_the_money?).and_return(true)

        expect { option.intrinsic }.to raise_error(ArgumentError, /underlying_price is nil/)
      end
    end
  end

  describe '#extrinsic' do
    context 'for OTM options' do
      it 'returns the mark value for OTM call' do
        option = described_class.new(
          symbol: 'SPXW241025C5800',
          underlying_symbol: 'SPX',
          strike: 5800,
          put_call: 'CALL',
          mark: 10.0,
          underlying_price: 5750,
          expiration_date: '2024-10-25'
        )

        expect(option.extrinsic).to eq(10.0)
      end

      it 'returns the mark value for OTM put' do
        option = described_class.new(
          symbol: 'SPXW241025P5800',
          underlying_symbol: 'SPX',
          strike: 5800,
          put_call: 'PUT',
          mark: 8.0,
          underlying_price: 5850,
          expiration_date: '2024-10-25'
        )

        expect(option.extrinsic).to eq(8.0)
      end

      it 'caches the calculated value' do
        option = described_class.new(
          symbol: 'SPXW241025C5800',
          underlying_symbol: 'SPX',
          strike: 5800,
          put_call: 'CALL',
          mark: 10.0,
          underlying_price: 5750,
          expiration_date: '2024-10-25'
        )

        first_call = option.extrinsic
        second_call = option.extrinsic

        expect(first_call).to eq(second_call)
        expect(first_call).to eq(10.0)
      end
    end

    context 'for ITM options' do
      it 'calculates extrinsic for ITM call' do
        # Underlying: 5850, Strike: 5800
        # Intrinsic: 5850 - 5800 = 50
        # Mark: 60
        # Extrinsic: 60 - 50 = 10
        option = described_class.new(
          symbol: 'SPXW241025C5800',
          underlying_symbol: 'SPX',
          strike: 5800,
          put_call: 'CALL',
          mark: 60.0,
          underlying_price: 5850,
          expiration_date: '2024-10-25'
        )

        expect(option.extrinsic).to eq(10.0)
      end

      it 'calculates extrinsic for ITM put' do
        # Underlying: 5750, Strike: 5800
        # Intrinsic: 5800 - 5750 = 50
        # Mark: 55
        # Extrinsic: 55 - 50 = 5
        option = described_class.new(
          symbol: 'SPXW241025P5800',
          underlying_symbol: 'SPX',
          strike: 5800,
          put_call: 'PUT',
          mark: 55.0,
          underlying_price: 5750,
          expiration_date: '2024-10-25'
        )

        expect(option.extrinsic).to eq(5.0)
      end

      it 'raises error when underlying_price is nil for ITM option' do
        option = described_class.new(
          symbol: 'SPXW241025C5800',
          underlying_symbol: 'SPX',
          strike: 5800,
          put_call: 'CALL',
          mark: 60.0,
          underlying_price: nil,
          expiration_date: '2024-10-25'
        )

        # Manually set in_the_money to trigger the error path
        allow(option).to receive(:in_the_money?).and_return(true)

        expect { option.extrinsic }.to raise_error(ArgumentError, /underlying_price is nil/)
      end

      it 'returns nil when mark is nil for ITM option' do
        option = described_class.new(
          symbol: 'SPXW241025C5800',
          underlying_symbol: 'SPX',
          strike: 5800,
          put_call: 'CALL',
          mark: nil,
          underlying_price: 5850,
          expiration_date: '2024-10-25'
        )

        expect(option.extrinsic).to be_nil
      end
    end
  end
end
