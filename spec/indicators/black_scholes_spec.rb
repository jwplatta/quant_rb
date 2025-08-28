# frozen_string_literal: true

require 'spec_helper'

RSpec.describe OptionsTrader::Indicators::BlackScholes do
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

  describe '.calculate' do
    let(:base_params) do
      {
        spot_price: 100,
        strike_price: 100,
        time_to_expiry: 0.25,
        risk_free_rate: 0.05,
        volatility: 0.20
      }
    end

    context 'for call options' do
      it 'calculates call option price' do
        result = described_class.calculate(**base_params, option_type: OptionsTrader::CALL)
        expect(result).to be > 0
        expect(result).to be_within(0.01).of(4.61)
      end

      it 'calculates higher price for in-the-money calls' do
        itm_result = described_class.calculate(**base_params.merge(strike_price: 95), option_type: OptionsTrader::CALL)
        atm_result = described_class.calculate(**base_params, option_type: OptionsTrader::CALL)
        expect(itm_result).to be > atm_result
      end

      it 'calculates lower price for out-of-the-money calls' do
        otm_result = described_class.calculate(**base_params.merge(strike_price: 105), option_type: OptionsTrader::CALL)
        atm_result = described_class.calculate(**base_params, option_type: OptionsTrader::CALL)
        expect(otm_result).to be < atm_result
      end
    end

    context 'for put options' do
      it 'calculates put option price' do
        result = described_class.calculate(**base_params, option_type: OptionsTrader::PUT)
        expect(result).to be > 0
        expect(result).to be_within(0.01).of(3.37)
      end

      it 'calculates higher price for in-the-money puts' do
        itm_result = described_class.calculate(**base_params.merge(strike_price: 105), option_type: OptionsTrader::PUT)
        atm_result = described_class.calculate(**base_params, option_type: OptionsTrader::PUT)
        expect(itm_result).to be > atm_result
      end

      it 'calculates lower price for out-of-the-money puts' do
        otm_result = described_class.calculate(**base_params.merge(strike_price: 95), option_type: OptionsTrader::PUT)
        atm_result = described_class.calculate(**base_params, option_type: OptionsTrader::PUT)
        expect(otm_result).to be < atm_result
      end
    end

    context 'with dividend yield' do
      it 'calculates different price with non-zero dividend yield' do
        no_div_result = described_class.calculate(**base_params, option_type: OptionsTrader::CALL)
        with_div_result = described_class.calculate(**base_params, option_type: OptionsTrader::CALL, dividend_yield: 0.03)
        expect(with_div_result).not_to eq(no_div_result)
        expect(with_div_result).to be < no_div_result
      end
    end

    context 'parameter validation' do
      it 'raises error for invalid option type' do
        expect {
          described_class.calculate(**base_params, option_type: 'INVALID')
        }.to raise_error(ArgumentError, 'option_type must be CALL or PUT')
      end

      it 'handles zero time to expiry' do
        expect {
          described_class.calculate(**base_params.merge(time_to_expiry: 0), option_type: OptionsTrader::CALL)
        }.not_to raise_error
      end
    end
  end
end
