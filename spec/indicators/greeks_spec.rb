# frozen_string_literal: true

require 'spec_helper'

RSpec.describe OptionsTrader::Indicators::Greeks do
  describe OptionsTrader::Indicators::Greeks::BlackScholes do
    describe '.norm_cdf' do
      it 'calculates standard normal cumulative distribution function' do
        expect(described_class.norm_cdf(0)).to be_within(0.0001).of(0.5)
        expect(described_class.norm_cdf(1)).to be_within(0.0001).of(0.8413)
        expect(described_class.norm_cdf(-1)).to be_within(0.0001).of(0.1587)
        expect(described_class.norm_cdf(2)).to be_within(0.0001).of(0.9772)
      end
    end

    describe '.norm_pdf' do
      it 'calculates standard normal probability density function' do
        expect(described_class.norm_pdf(0)).to be_within(0.0001).of(0.3989)
        expect(described_class.norm_pdf(1)).to be_within(0.0001).of(0.2420)
        expect(described_class.norm_pdf(-1)).to be_within(0.0001).of(0.2420)
        expect(described_class.norm_pdf(2)).to be_within(0.0001).of(0.0540)
      end
    end

    describe '.d1' do
      it 'calculates d1 for Black-Scholes model' do
        result = described_class.d1(100, 100, 0.25, 0.05, 0.20)
        expect(result).to be_within(0.0001).of(0.1750)
      end
    end

    describe '.d2' do
      it 'calculates d2 for Black-Scholes model' do
        result = described_class.d2(100, 100, 0.25, 0.05, 0.20)
        expect(result).to be_within(0.0001).of(0.0750)
      end
    end
  end

  describe OptionsTrader::Indicators::Greeks::Delta do
    let(:base_params) do
      {
        spot_price: 100,
        strike_price: 100,
        time_to_expiry: 0.25,
        risk_free_rate: 0.05,
        volatility: 0.20
      }
    end

    describe '.calculate' do
      context 'for call options' do
        it 'calculates positive delta for at-the-money call' do
          result = described_class.calculate(**base_params, option_type: :call)
          expect(result).to be > 0.5
          expect(result).to be < 0.6
        end

        it 'calculates delta close to 1 for deep in-the-money call' do
          params = base_params.merge(strike_price: 80)
          result = described_class.calculate(**params, option_type: :call)
          expect(result).to be > 0.9
        end

        it 'calculates delta close to 0 for deep out-of-the-money call' do
          params = base_params.merge(strike_price: 120)
          result = described_class.calculate(**params, option_type: :call)
          expect(result).to be < 0.1
        end
      end

      context 'for put options' do
        it 'calculates negative delta for at-the-money put' do
          result = described_class.calculate(**base_params, option_type: :put)
          expect(result).to be < -0.4
          expect(result).to be > -0.5
        end

        it 'calculates delta close to -1 for deep in-the-money put' do
          params = base_params.merge(strike_price: 120)
          result = described_class.calculate(**params, option_type: :put)
          expect(result).to be < -0.9
        end

        it 'calculates delta close to 0 for deep out-of-the-money put' do
          params = base_params.merge(strike_price: 80)
          result = described_class.calculate(**params, option_type: :put)
          expect(result).to be > -0.1
        end
      end

      it 'raises error for invalid option type' do
        expect {
          described_class.calculate(**base_params, option_type: :invalid)
        }.to raise_error(ArgumentError, "option_type must be :call or :put")
      end
    end
  end

  describe OptionsTrader::Indicators::Greeks::Gamma do
    let(:base_params) do
      {
        spot_price: 100,
        strike_price: 100,
        time_to_expiry: 0.25,
        risk_free_rate: 0.05,
        volatility: 0.20
      }
    end

    describe '.calculate' do
      it 'calculates positive gamma for at-the-money option' do
        result = described_class.calculate(**base_params)
        expect(result).to be > 0
        expect(result).to be_within(0.001).of(0.0393)
      end

      it 'calculates higher gamma for shorter time to expiry' do
        short_term = described_class.calculate(**base_params.merge(time_to_expiry: 0.05))
        long_term = described_class.calculate(**base_params.merge(time_to_expiry: 1.0))
        expect(short_term).to be > long_term
      end

      it 'calculates lower gamma for out-of-the-money options' do
        atm_gamma = described_class.calculate(**base_params)
        otm_gamma = described_class.calculate(**base_params.merge(strike_price: 120))
        expect(atm_gamma).to be > otm_gamma
      end
    end
  end

  describe OptionsTrader::Indicators::Greeks::Vega do
    let(:base_params) do
      {
        spot_price: 100,
        strike_price: 100,
        time_to_expiry: 0.25,
        risk_free_rate: 0.05,
        volatility: 0.20
      }
    end

    describe '.calculate' do
      it 'calculates positive vega for at-the-money option' do
        result = described_class.calculate(**base_params)
        expect(result).to be > 0
        expect(result).to be_within(0.1).of(19.6)
      end

      it 'calculates higher vega for longer time to expiry' do
        long_term = described_class.calculate(**base_params.merge(time_to_expiry: 1.0))
        short_term = described_class.calculate(**base_params.merge(time_to_expiry: 0.05))
        expect(long_term).to be > short_term
      end

      it 'calculates lower vega for out-of-the-money options' do
        atm_vega = described_class.calculate(**base_params)
        otm_vega = described_class.calculate(**base_params.merge(strike_price: 120))
        expect(atm_vega).to be > otm_vega
      end
    end
  end

  describe OptionsTrader::Indicators::Greeks::Theta do
    let(:base_params) do
      {
        spot_price: 100,
        strike_price: 100,
        time_to_expiry: 0.25,
        risk_free_rate: 0.05,
        volatility: 0.20
      }
    end

    describe '.calculate' do
      context 'for call options' do
        it 'calculates negative theta for at-the-money call' do
          result = described_class.calculate(**base_params, option_type: :call)
          expect(result).to be < 0
          expect(result).to be_within(1).of(-10.5)
        end

        it 'calculates more negative theta for shorter time to expiry' do
          short_term = described_class.calculate(**base_params.merge(time_to_expiry: 0.05), option_type: :call)
          long_term = described_class.calculate(**base_params.merge(time_to_expiry: 1.0), option_type: :call)
          expect(short_term).to be < long_term
        end
      end

      context 'for put options' do
        it 'calculates negative theta for at-the-money put' do
          result = described_class.calculate(**base_params, option_type: :put)
          expect(result).to be < 0
        end

        it 'calculates different theta for puts vs calls' do
          call_theta = described_class.calculate(**base_params, option_type: :call)
          put_theta = described_class.calculate(**base_params, option_type: :put)
          expect(call_theta).not_to eq(put_theta)
        end
      end

      it 'raises error for invalid option type' do
        expect {
          described_class.calculate(**base_params, option_type: :invalid)
        }.to raise_error(ArgumentError, "option_type must be :call or :put")
      end
    end
  end

  describe OptionsTrader::Indicators::Greeks::Rho do
    let(:base_params) do
      {
        spot_price: 100,
        strike_price: 100,
        time_to_expiry: 0.25,
        risk_free_rate: 0.05,
        volatility: 0.20
      }
    end

    describe '.calculate' do
      context 'for call options' do
        it 'calculates positive rho for at-the-money call' do
          result = described_class.calculate(**base_params, option_type: :call)
          expect(result).to be > 0
          expect(result).to be_within(1).of(13.1)
        end

        it 'calculates higher rho for longer time to expiry' do
          long_term = described_class.calculate(**base_params.merge(time_to_expiry: 1.0), option_type: :call)
          short_term = described_class.calculate(**base_params.merge(time_to_expiry: 0.05), option_type: :call)
          expect(long_term).to be > short_term
        end
      end

      context 'for put options' do
        it 'calculates negative rho for at-the-money put' do
          result = described_class.calculate(**base_params, option_type: :put)
          expect(result).to be < 0
          expect(result).to be_within(1).of(-11.9)
        end

        it 'calculates opposite sign rho for puts vs calls' do
          call_rho = described_class.calculate(**base_params, option_type: :call)
          put_rho = described_class.calculate(**base_params, option_type: :put)
          expect(call_rho).to be > 0
          expect(put_rho).to be < 0
        end
      end

      it 'raises error for invalid option type' do
        expect {
          described_class.calculate(**base_params, option_type: :invalid)
        }.to raise_error(ArgumentError, "option_type must be :call or :put")
      end
    end
  end
end