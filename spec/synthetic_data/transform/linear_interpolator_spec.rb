require 'spec_helper'

RSpec.describe OptionsTrader::SyntheticData::Transform::LinearInterpolator do
  let(:underlying_price) { 5800.0 }
  let(:expiration_date) { Date.today + 1 }

  def create_option(strike:, mark:, contract_type:, extrinsic: nil)
    OptionsTrader::DataObjects::Option.new(
      symbol: "SPX#{expiration_date.strftime('%y%m%d')}#{contract_type[0]}#{(strike * 1000).to_i}",
      underlying_symbol: '$SPX',
      strike: strike,
      put_call: contract_type,
      mark: mark,
      underlying_price: underlying_price,
      expiration_date: expiration_date,
      days_to_expiration: 1,
      extrinsic: extrinsic
    )
  end

  describe '.interpolate' do
    context 'with OTM calls' do
      it 'interpolates missing marks for OTM options' do
        options = [
          create_option(strike: 5900, mark: 10.0, contract_type: 'CALL'),
          create_option(strike: 5905, mark: nil, contract_type: 'CALL'),
          create_option(strike: 5910, mark: 8.0, contract_type: 'CALL')
        ]

        result = described_class.interpolate(options, contract_type: 'CALL')

        expect(result[1].mark).to eq(9.0)
      end

      it 'applies minimum extrinsic value' do
        options = [
          create_option(strike: 5900, mark: 0.05, contract_type: 'CALL'),
          create_option(strike: 5905, mark: nil, contract_type: 'CALL'),
          create_option(strike: 5910, mark: 0.03, contract_type: 'CALL')
        ]

        result = described_class.interpolate(options, contract_type: 'CALL', min_extrinsic: 0.025)

        expect(result[1].mark).to eq(0.04)
      end
    end

    context 'with ITM calls' do
      it 'interpolates extrinsic value for ITM options' do
        options = [
          create_option(strike: 5700, mark: 105.0, contract_type: 'CALL'),
          create_option(strike: 5705, mark: nil, contract_type: 'CALL'),
          create_option(strike: 5710, mark: 95.0, contract_type: 'CALL')
        ]

        result = described_class.interpolate(options, contract_type: 'CALL')

        # strike 5705 should have interpolated extrinsic value
        # and mark = extrinsic + intrinsic
        expect(result[1].mark).not_to be_nil
        expect(result[1].extrinsic).not_to be_nil
      end
    end

    context 'with OTM puts' do
      it 'interpolates missing marks for OTM options' do
        options = [
          create_option(strike: 5700, mark: 8.0, contract_type: 'PUT'),
          create_option(strike: 5705, mark: nil, contract_type: 'PUT'),
          create_option(strike: 5710, mark: 10.0, contract_type: 'PUT')
        ]

        result = described_class.interpolate(options, contract_type: 'PUT')

        expect(result[1].mark).to eq(9.0)
      end
    end

    context 'monotonicity validation' do
      it 'raises error when call prices are not monotonically decreasing' do
        options = [
          create_option(strike: 5900, mark: 8.0, contract_type: 'CALL'),
          create_option(strike: 5905, mark: nil, contract_type: 'CALL'),
          create_option(strike: 5910, mark: 10.0, contract_type: 'CALL') # violation: increasing
        ]

        expect {
          described_class.interpolate(options, contract_type: 'CALL')
        }.to raise_error(/Non-monotonic prices detected/)
      end

      it 'raises error when put prices are not monotonically increasing' do
        options = [
          create_option(strike: 5700, mark: 10.0, contract_type: 'PUT'),
          create_option(strike: 5705, mark: nil, contract_type: 'PUT'),
          create_option(strike: 5710, mark: 8.0, contract_type: 'PUT') # violation: decreasing
        ]

        expect {
          described_class.interpolate(options, contract_type: 'PUT')
        }.to raise_error(/Non-monotonic prices detected/)
      end

      it 'allows monotonic call prices to pass validation' do
        options = [
          create_option(strike: 5900, mark: 10.0, contract_type: 'CALL'),
          create_option(strike: 5905, mark: nil, contract_type: 'CALL'),
          create_option(strike: 5910, mark: 8.0, contract_type: 'CALL')
        ]

        expect {
          described_class.interpolate(options, contract_type: 'CALL')
        }.not_to raise_error
      end
    end

    context 'with only one bound' do
      it 'uses minimum extrinsic when only lower bound exists' do
        options = [
          create_option(strike: 5900, mark: 10.0, contract_type: 'CALL'),
          create_option(strike: 5905, mark: nil, contract_type: 'CALL')
        ]

        result = described_class.interpolate(options, contract_type: 'CALL', min_extrinsic: 0.025)

        expect(result[1].mark).to eq(0.025)
      end

      it 'uses minimum extrinsic when only upper bound exists' do
        options = [
          create_option(strike: 5900, mark: nil, contract_type: 'CALL'),
          create_option(strike: 5905, mark: 8.0, contract_type: 'CALL')
        ]

        result = described_class.interpolate(options, contract_type: 'CALL', min_extrinsic: 0.025)

        expect(result[0].mark).to eq(0.025)
      end
    end
  end
end
