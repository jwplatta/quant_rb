require 'spec_helper'

RSpec.describe OptionsTrader::SyntheticData::Transform::LinearInterpolator do
  let(:underlying_price) { 5800.0 }
  let(:expiration_date) { Date.today + 1 }

  def create_option(strike:, mark:, contract_type:, extrinsic: nil)
    # Calculate intrinsic value based on moneyness
    intrinsic = if contract_type == 'CALL'
      underlying_price > strike ? underlying_price - strike : 0.0
    else # PUT
      strike > underlying_price ? strike - underlying_price : 0.0
    end

    # If mark is provided and extrinsic is not, calculate extrinsic from mark
    if mark && !extrinsic
      extrinsic = mark - intrinsic
    end

    OptionsTrader::DataObjects::Option.new(
      symbol: "SPX#{expiration_date.strftime('%y%m%d')}#{contract_type[0]}#{(strike * 1000).to_i}",
      underlying_symbol: '$SPX',
      strike: strike,
      put_call: contract_type,
      mark: mark,
      underlying_price: underlying_price,
      expiration_date: expiration_date,
      days_to_expiration: 1,
      intrinsic: intrinsic,
      extrinsic: extrinsic
    )
  end

  describe '.interpolate' do
    context 'with OTM calls' do
      it 'interpolates extrinsic value for single missing option' do
        options = [
          create_option(strike: 5900, mark: 10.0, contract_type: 'CALL'),
          create_option(strike: 5905, mark: nil, contract_type: 'CALL'),
          create_option(strike: 5910, mark: 8.0, contract_type: 'CALL')
        ]

        result = described_class.interpolate(options, contract_type: 'CALL')

        # For OTM options, extrinsic = mark
        # Interpolated extrinsic should be (10.0 + 8.0) / 2 = 9.0
        expect(result[1].mark).to eq(9.0)
        expect(result[1].extrinsic).to eq(9.0)
      end

      it 'interpolates extrinsic value for multiple consecutive missing options' do
        options = [
          create_option(strike: 5900, mark: 12.0, contract_type: 'CALL'),
          create_option(strike: 5905, mark: nil, contract_type: 'CALL'),
          create_option(strike: 5910, mark: nil, contract_type: 'CALL'),
          create_option(strike: 5915, mark: 6.0, contract_type: 'CALL')
        ]

        result = described_class.interpolate(options, contract_type: 'CALL')

        # Linear interpolation: slope = (6.0 - 12.0) / (5915 - 5900) = -0.4
        # 5905: 12.0 + (-0.4 * 5) = 10.0
        # 5910: 12.0 + (-0.4 * 10) = 8.0
        expect(result[1].extrinsic).to eq(10.0)
        expect(result[1].mark).to eq(10.0)
        expect(result[2].extrinsic).to eq(8.0)
        expect(result[2].mark).to eq(8.0)
      end

      it 'applies minimum extrinsic value when interpolated value is too low' do
        options = [
          create_option(strike: 5900, mark: 0.05, contract_type: 'CALL'),
          create_option(strike: 5905, mark: nil, contract_type: 'CALL'),
          create_option(strike: 5910, mark: 0.03, contract_type: 'CALL')
        ]

        result = described_class.interpolate(options, contract_type: 'CALL', min_extrinsic: 0.025)

        # Interpolated would be 0.04, but min is 0.025, so 0.04 is used
        expect(result[1].extrinsic).to eq(0.04)
        expect(result[1].mark).to eq(0.04)
      end

      it 'enforces minimum extrinsic when interpolated value would be below minimum' do
        options = [
          create_option(strike: 5900, mark: 0.05, contract_type: 'CALL'),
          create_option(strike: 5905, mark: nil, contract_type: 'CALL'),
          create_option(strike: 5910, mark: 0.01, contract_type: 'CALL')
        ]

        result = described_class.interpolate(options, contract_type: 'CALL', min_extrinsic: 0.025)

        # Interpolated would be 0.03, which is above min, so 0.03 is used
        expect(result[1].extrinsic).to be_within(0.001).of(0.03)
        expect(result[1].mark).to be_within(0.001).of(0.03)
      end
    end

    context 'with ITM calls' do
      it 'interpolates extrinsic value for single missing ITM option' do
        options = [
          create_option(strike: 5700, mark: 105.0, contract_type: 'CALL'),
          create_option(strike: 5705, mark: nil, contract_type: 'CALL'),
          create_option(strike: 5710, mark: 95.0, contract_type: 'CALL')
        ]

        result = described_class.interpolate(options, contract_type: 'CALL')

        # For ITM calls: intrinsic = underlying_price - strike
        # 5700: intrinsic = 5800 - 5700 = 100, extrinsic = 105 - 100 = 5.0
        # 5710: intrinsic = 5800 - 5710 = 90, extrinsic = 95 - 90 = 5.0
        # 5705: interpolated extrinsic = 5.0 (constant)
        #       intrinsic = 5800 - 5705 = 95
        #       mark = 95 + 5.0 = 100.0
        expect(result[1].extrinsic).to eq(5.0)
        expect(result[1].mark).to eq(100.0)
      end

      it 'interpolates extrinsic value for multiple consecutive missing ITM options' do
        options = [
          create_option(strike: 5700, mark: 106.0, contract_type: 'CALL'),
          create_option(strike: 5705, mark: nil, contract_type: 'CALL'),
          create_option(strike: 5710, mark: nil, contract_type: 'CALL'),
          create_option(strike: 5715, mark: 90.0, contract_type: 'CALL')
        ]

        result = described_class.interpolate(options, contract_type: 'CALL')

        # 5700: intrinsic = 100, extrinsic = 6.0
        # 5715: intrinsic = 85, extrinsic = 5.0
        # slope = (5.0 - 6.0) / (5715 - 5700) = -1.0 / 15 = -0.0667
        # 5705: extrinsic = 6.0 + (-0.0667 * 5) = 5.67 (rounded)
        # 5710: extrinsic = 6.0 + (-0.0667 * 10) = 5.33 (rounded)
        expect(result[1].extrinsic).to be_within(0.01).of(5.67)
        expect(result[2].extrinsic).to be_within(0.01).of(5.33)
        expect(result[1].mark).not_to be_nil
        expect(result[2].mark).not_to be_nil
      end
    end

    context 'with OTM puts' do
      it 'interpolates extrinsic value for OTM puts' do
        options = [
          create_option(strike: 5700, mark: 8.0, contract_type: 'PUT'),
          create_option(strike: 5705, mark: nil, contract_type: 'PUT'),
          create_option(strike: 5710, mark: 10.0, contract_type: 'PUT')
        ]

        result = described_class.interpolate(options, contract_type: 'PUT')

        # Linear interpolation: (8.0 + 10.0) / 2 = 9.0
        expect(result[1].extrinsic).to eq(9.0)
        expect(result[1].mark).to eq(9.0)
      end

      it 'interpolates extrinsic value for multiple consecutive missing OTM puts' do
        options = [
          create_option(strike: 5700, mark: 6.0, contract_type: 'PUT'),
          create_option(strike: 5705, mark: nil, contract_type: 'PUT'),
          create_option(strike: 5710, mark: nil, contract_type: 'PUT'),
          create_option(strike: 5715, mark: 12.0, contract_type: 'PUT')
        ]

        result = described_class.interpolate(options, contract_type: 'PUT')

        # slope = (12.0 - 6.0) / (5715 - 5700) = 0.4
        # 5705: 6.0 + (0.4 * 5) = 8.0
        # 5710: 6.0 + (0.4 * 10) = 10.0
        expect(result[1].extrinsic).to eq(8.0)
        expect(result[1].mark).to eq(8.0)
        expect(result[2].extrinsic).to eq(10.0)
        expect(result[2].mark).to eq(10.0)
      end
    end

    context 'with ITM puts' do
      it 'interpolates extrinsic value for ITM puts' do
        options = [
          create_option(strike: 5900, mark: 106.0, contract_type: 'PUT'),
          create_option(strike: 5905, mark: nil, contract_type: 'PUT'),
          create_option(strike: 5910, mark: 116.0, contract_type: 'PUT')
        ]

        result = described_class.interpolate(options, contract_type: 'PUT')

        # 5900: intrinsic = 5900 - 5800 = 100, extrinsic = 6.0
        # 5910: intrinsic = 5910 - 5800 = 110, extrinsic = 6.0
        # 5905: interpolated extrinsic = 6.0 (constant)
        #       intrinsic = 105
        #       mark = 105 + 6.0 = 111.0
        expect(result[1].extrinsic).to eq(6.0)
        expect(result[1].mark).to eq(111.0)
      end
    end

    context 'with only one bound' do
      it 'uses minimum extrinsic when only lower bound exists' do
        options = [
          create_option(strike: 5900, mark: 10.0, contract_type: 'CALL'),
          create_option(strike: 5905, mark: nil, contract_type: 'CALL')
        ]

        result = described_class.interpolate(options, contract_type: 'CALL', min_extrinsic: 0.025)

        expect(result[1].extrinsic).to eq(0.025)
        expect(result[1].mark).to eq(0.025)
      end

      it 'uses minimum extrinsic when only upper bound exists' do
        options = [
          create_option(strike: 5900, mark: nil, contract_type: 'CALL'),
          create_option(strike: 5905, mark: 8.0, contract_type: 'CALL')
        ]

        result = described_class.interpolate(options, contract_type: 'CALL', min_extrinsic: 0.025)

        expect(result[0].extrinsic).to eq(0.025)
        expect(result[0].mark).to eq(0.025)
      end

      it 'uses minimum extrinsic for multiple options with only one bound' do
        options = [
          create_option(strike: 5900, mark: 10.0, contract_type: 'CALL'),
          create_option(strike: 5905, mark: nil, contract_type: 'CALL'),
          create_option(strike: 5910, mark: nil, contract_type: 'CALL')
        ]

        result = described_class.interpolate(options, contract_type: 'CALL', min_extrinsic: 0.05)

        expect(result[1].extrinsic).to eq(0.05)
        expect(result[1].mark).to eq(0.05)
        expect(result[2].extrinsic).to eq(0.05)
        expect(result[2].mark).to eq(0.05)
      end
    end

    context 'with no bounds' do
      it 'raises an error when no bounds are found' do
        options = [
          create_option(strike: 5900, mark: nil, contract_type: 'CALL'),
          create_option(strike: 5905, mark: nil, contract_type: 'CALL')
        ]

        expect {
          described_class.interpolate(options, contract_type: 'CALL')
        }.to raise_error(/Cannot interpolate options/)
      end
    end

    context 'preserves original options' do
      it 'does not modify the original array' do
        options = [
          create_option(strike: 5900, mark: 10.0, contract_type: 'CALL'),
          create_option(strike: 5905, mark: nil, contract_type: 'CALL'),
          create_option(strike: 5910, mark: 8.0, contract_type: 'CALL')
        ]

        original_marks = options.map(&:mark)
        described_class.interpolate(options, contract_type: 'CALL')

        expect(options.map(&:mark)).to eq(original_marks)
      end
    end
  end
end
