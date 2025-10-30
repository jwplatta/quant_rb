require 'spec_helper'

RSpec.describe OptionsTrader::SyntheticData::Transform::LinearInterpolator do
  let(:underlying_price) { 5800.0 }
  let(:expiration_date) { Date.today + 1 }

  def create_option(strike:, mark:, contract_type:, extrinsic: nil)
    # Calculate intrinsic value based on moneyness
    intrinsic = if contract_type == OptionsTrader::CALL
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

  describe '#set_boundary_extrinsics!' do
    it 'sets boundary options extrinsic when nil' do
      options = [
        create_option(strike: 5700, mark: nil, contract_type: OptionsTrader::CALL),
        create_option(strike: 5750, mark: 60.0, contract_type: OptionsTrader::CALL),
        create_option(strike: 5775, mark: 45.0, contract_type: OptionsTrader::CALL),
        create_option(strike: 5800, mark: 30.0, contract_type: OptionsTrader::CALL),
        create_option(strike: 5850, mark: 15.0, contract_type: OptionsTrader::CALL),
        create_option(strike: 5900, mark: nil, contract_type: OptionsTrader::CALL)
      ].sort_by { |opt| -opt.strike }

      described_class.new(min_otm_extrinsic: 0.025, min_itm_extrinsic: 26.0).set_boundary_extrinsics!(options)
      strike_5700 = options.find { |opt| opt.strike == 5700 }
      strike_5900 = options.find { |opt| opt.strike == 5900 }

      expect(strike_5700.extrinsic).to eq(26.0)
      expect(strike_5900.extrinsic).to eq(0.025)
    end
  end

  describe '.interpolate' do
    context 'with OTM calls' do
      it 'interpolates extrinsic value for single missing option' do
        options = [
          create_option(strike: 5700, mark: 26.0, contract_type: OptionsTrader::CALL),
          create_option(strike: 5750, mark: 60.0, contract_type: OptionsTrader::CALL),
          create_option(strike: 5775, mark: 45.0, contract_type: OptionsTrader::CALL),
          create_option(strike: 5900, mark: 10.0, contract_type: OptionsTrader::CALL),
          create_option(strike: 5905, mark: nil, contract_type: OptionsTrader::CALL),
          create_option(strike: 5910, mark: 8.0, contract_type: OptionsTrader::CALL)
        ]

        result = described_class.interpolate(options)

        # For OTM options, extrinsic = mark
        # Interpolated extrinsic should be (10.0 + 8.0) / 2 = 9.0

        strike_5905 = result.find { |opt| opt.strike == 5905 }
        expect(strike_5905.extrinsic).to eq(9.0)
        expect(strike_5905.mark).to eq(9.0)
      end

      it 'interpolates extrinsic value for multiple consecutive missing options' do
        options = [
          create_option(strike: 5700, mark: 26.0, contract_type: OptionsTrader::CALL),
          create_option(strike: 5750, mark: 60.0, contract_type: OptionsTrader::CALL),
          create_option(strike: 5775, mark: 45.0, contract_type: OptionsTrader::CALL),
          create_option(strike: 5900, mark: 12.0, contract_type: OptionsTrader::CALL),
          create_option(strike: 5905, mark: nil, contract_type: OptionsTrader::CALL),
          create_option(strike: 5910, mark: nil, contract_type: OptionsTrader::CALL),
          create_option(strike: 5915, mark: 6.0, contract_type: OptionsTrader::CALL)
        ]

        result = described_class.interpolate(options)
        # Linear interpolation: slope = (6.0 - 12.0) / (5915 - 5900) = -0.4
        # 5905: 12.0 + (-0.4 * 5) = 10.0
        # 5910: 12.0 + (-0.4 * 10) = 8.0

        strike_5905 = result.find { |opt| opt.strike == 5905 }
        strike_5910 = result.find { |opt| opt.strike == 5910 }
        expect(strike_5905.extrinsic).to eq(10.0)
        expect(strike_5905.mark).to eq(10.0)
        expect(strike_5910.extrinsic).to eq(8.0)
        expect(strike_5910.mark).to eq(8.0)
      end
    end

    context 'with ITM calls' do
      it 'interpolates extrinsic value for single missing ITM option' do
        options = [
          create_option(strike: 5700, mark: 105.0, contract_type: OptionsTrader::CALL),
          create_option(strike: 5705, mark: nil, contract_type: OptionsTrader::CALL),
          create_option(strike: 5710, mark: 95.0, contract_type: OptionsTrader::CALL),
          create_option(strike: 5900, mark: 12.0, contract_type: OptionsTrader::CALL),
          create_option(strike: 5905, mark: 10.0, contract_type: OptionsTrader::CALL),
          create_option(strike: 5910, mark: 8.0, contract_type: OptionsTrader::CALL),
          create_option(strike: 5915, mark: 6.0, contract_type: OptionsTrader::CALL)
        ]

        result = described_class.interpolate(options)

        # For ITM calls: intrinsic = underlying_price - strike
        # 5700: intrinsic = 5800 - 5700 = 100, extrinsic = 105 - 100 = 5.0
        # 5710: intrinsic = 5800 - 5710 = 90, extrinsic = 95 - 90 = 5.0
        # 5705: interpolated extrinsic = 5.0 (constant)
        #       intrinsic = 5800 - 5705 = 95
        #       mark = 95 + 5.0 = 100.0
        strike_5705 = result.find { |opt| opt.strike == 5705 }
        expect(strike_5705.extrinsic).to eq(5.0)
        expect(strike_5705.mark).to eq(100.0)
      end

      it 'interpolates extrinsic value for multiple consecutive missing ITM options' do
        options = [
          create_option(strike: 5700, mark: 106.0, contract_type: OptionsTrader::CALL),
          create_option(strike: 5705, mark: nil, contract_type: OptionsTrader::CALL),
          create_option(strike: 5710, mark: nil, contract_type: OptionsTrader::CALL),
          create_option(strike: 5715, mark: 90.0, contract_type: OptionsTrader::CALL),
          create_option(strike: 5900, mark: 12.0, contract_type: OptionsTrader::CALL),
          create_option(strike: 5905, mark: 10.0, contract_type: OptionsTrader::CALL),
          create_option(strike: 5910, mark: 8.0, contract_type: OptionsTrader::CALL),
          create_option(strike: 5915, mark: 6.0, contract_type: OptionsTrader::CALL)
        ]

        result = described_class.interpolate(options)

        # 5700: intrinsic = 100, extrinsic = 6.0
        # 5715: intrinsic = 85, extrinsic = 5.0
        # slope = (5.0 - 6.0) / (5715 - 5700) = -1.0 / 15 = -0.0667
        # 5705: extrinsic = 6.0 + (-0.0667 * 5) = 5.67 (rounded)
        # 5710: extrinsic = 6.0 + (-0.0667 * 10) = 5.33 (rounded)

        strike_5705 = result.find { |opt| opt.strike == 5705 }
        strike_5710 = result.find { |opt| opt.strike == 5710 }
        expect(strike_5705.extrinsic).to be_within(0.01).of(5.67)
        expect(strike_5705.mark).to be_within(0.01).of(100.67)
        expect(strike_5710.extrinsic).to be_within(0.01).of(5.33)
        expect(strike_5710.mark).to be_within(0.01).of(95.33)
      end
    end

    context 'with OTM puts' do
      it 'interpolates extrinsic value for OTM puts' do
        options = [
          create_option(strike: 5900, mark: 106.0, contract_type: OptionsTrader::PUT),
          create_option(strike: 5905, mark: 110.0, contract_type: OptionsTrader::PUT),
          create_option(strike: 5910, mark: 116.0, contract_type: OptionsTrader::PUT),
          create_option(strike: 5700, mark: 8.0, contract_type: OptionsTrader::PUT),
          create_option(strike: 5705, mark: nil, contract_type: OptionsTrader::PUT),
          create_option(strike: 5710, mark: 10.0, contract_type: OptionsTrader::PUT)
        ]

        result = described_class.interpolate(options)

        # Linear interpolation: (8.0 + 10.0) / 2 = 9.0
        strike_5705 = result.find { |opt| opt.strike == 5705 }
        expect(strike_5705.extrinsic).to eq(9.0)
        expect(strike_5705.mark).to eq(9.0)
      end

      it 'interpolates extrinsic value for multiple consecutive missing OTM puts' do
        options = [
          create_option(strike: 5700, mark: 6.0, contract_type: OptionsTrader::PUT),
          create_option(strike: 5705, mark: nil, contract_type: OptionsTrader::PUT),
          create_option(strike: 5710, mark: nil, contract_type: OptionsTrader::PUT),
          create_option(strike: 5715, mark: 12.0, contract_type: OptionsTrader::PUT),
          create_option(strike: 5900, mark: 106.0, contract_type: OptionsTrader::PUT),
          create_option(strike: 5905, mark: 110.0, contract_type: OptionsTrader::PUT),
          create_option(strike: 5910, mark: 116.0, contract_type: OptionsTrader::PUT)
        ]

        result = described_class.interpolate(options)

        # slope = (12.0 - 6.0) / (5715 - 5700) = 0.4
        # 5705: 6.0 + (0.4 * 5) = 8.0
        # 5710: 6.0 + (0.4 * 10) = 10.0

        strike_5705 = result.find { |opt| opt.strike == 5705 }
        strike_5710 = result.find { |opt| opt.strike == 5710 }
        expect(strike_5705.extrinsic).to eq(8.0)
        expect(strike_5705.mark).to eq(8.0)
        expect(strike_5710.extrinsic).to eq(10.0)
        expect(strike_5710.mark).to eq(10.0)
      end
    end

    context 'with ITM puts' do
      it 'interpolates extrinsic value for ITM puts' do
        options = [
          create_option(strike: 5500, mark: 0.025, contract_type: OptionsTrader::PUT),
          create_option(strike: 5600, mark: 5.0, contract_type: OptionsTrader::PUT),
          create_option(strike: 5700, mark: 10.0, contract_type: OptionsTrader::PUT),
          create_option(strike: 5900, mark: 106.0, contract_type: OptionsTrader::PUT),
          create_option(strike: 5905, mark: nil, contract_type: OptionsTrader::PUT),
          create_option(strike: 5910, mark: 116.0, contract_type: OptionsTrader::PUT)
        ]

        result = described_class.interpolate(options)

        # 5900: intrinsic = 5900 - 5800 = 100, extrinsic = 6.0
        # 5910: intrinsic = 5910 - 5800 = 110, extrinsic = 6.0
        # 5905: interpolated extrinsic = 6.0 (constant)
        #       intrinsic = 105
        #       mark = 105 + 6.0 = 111.0
        strike_5905 = result.find { |opt| opt.strike == 5905 }
        expect(strike_5905.extrinsic).to eq(6.0)
        expect(strike_5905.mark).to eq(111.0)
      end
    end

    context 'with only one bound' do
      it 'uses minimum extrinsic when only lower bound exists' do
        options = [
          create_option(strike: 5500, mark: 304, contract_type: OptionsTrader::CALL),
          create_option(strike: 5600, mark: 205, contract_type: OptionsTrader::CALL),
          create_option(strike: 5700, mark: 106, contract_type: OptionsTrader::CALL),
          create_option(strike: 5900, mark: 10.0, contract_type: OptionsTrader::CALL),
          create_option(strike: 5905, mark: 5.0, contract_type: OptionsTrader::CALL),
          create_option(strike: 5910, mark: nil, contract_type: OptionsTrader::CALL)
        ]

        result = described_class.interpolate(options, min_otm_extrinsic: 0.025, min_itm_extrinsic: 26.0)

        strike_5910 = result.find { |opt| opt.strike == 5910 }
        expect(strike_5910.extrinsic).to eq(0.025)
        expect(strike_5910.mark).to eq(0.025)
      end

      it 'raises an error when only upper bound exists (insufficient ITM options)' do
        options = [
          create_option(strike: 5900, mark: nil, contract_type: OptionsTrader::CALL),
          create_option(strike: 5905, mark: 8.0, contract_type: OptionsTrader::CALL)
        ]

        expect {
          described_class.interpolate(options, min_otm_extrinsic: 0.025, min_itm_extrinsic: 26.0)
        }.to raise_error(/Options must include at least 3 OTM and 3 ITM options/)
      end

      it 'uses min extrinsic for bound and interpolates the missing' do
        options = [
          create_option(strike: 5500, mark: 304, contract_type: OptionsTrader::CALL),
          create_option(strike: 5600, mark: 205, contract_type: OptionsTrader::CALL),
          create_option(strike: 5700, mark: 106, contract_type: OptionsTrader::CALL),
          create_option(strike: 5900, mark: 10.0, contract_type: OptionsTrader::CALL),
          create_option(strike: 5905, mark: nil, contract_type: OptionsTrader::CALL),
          create_option(strike: 5910, mark: nil, contract_type: OptionsTrader::CALL)
        ]

        result = described_class.interpolate(options, min_otm_extrinsic: 0.025, min_itm_extrinsic: 26.0)
        strike_5905 = result.find { |opt| opt.strike == 5905 }
        expect(strike_5905.extrinsic).to eq(5.0125)
        expect(strike_5905.mark).to eq(5.0125)
      end
    end
  end
end
