require 'spec_helper'

RSpec.describe OptionsTrader::Indicators::CoxRossRubinstein do
  let(:spot_price) { 100.0 }
  let(:strike_price) { 105.0 }
  let(:time_to_expiry) { 0.25 } # 3 months
  let(:risk_free_rate) { 0.05 } # 5%
  let(:volatility) { 0.2 } # 20%
  let(:steps) { 50 }

  describe '.calculate' do
    context 'with CALL options' do
      it 'returns a reasonable call option price' do
        price = described_class.calculate(
          spot_price: spot_price,
          strike_price: strike_price,
          time_to_expiry: time_to_expiry,
          risk_free_rate: risk_free_rate,
          volatility: volatility,
          option_type: OptionsTrader::CALL,
          steps: steps
        )

        expect(price).to be_a(Float)
        expect(price).to be > 0
        expect(price).to be < spot_price # Call price should be less than spot price
      end

      it 'prices in-the-money calls higher than out-of-the-money calls' do
        itm_price = described_class.calculate(
          spot_price: 110.0, # ITM: spot > strike
          strike_price: strike_price,
          time_to_expiry: time_to_expiry,
          risk_free_rate: risk_free_rate,
          volatility: volatility,
          option_type: OptionsTrader::CALL,
          steps: steps
        )

        otm_price = described_class.calculate(
          spot_price: 95.0, # OTM: spot < strike
          strike_price: strike_price,
          time_to_expiry: time_to_expiry,
          risk_free_rate: risk_free_rate,
          volatility: volatility,
          option_type: OptionsTrader::CALL,
          steps: steps
        )

        expect(itm_price).to be > otm_price
      end

      it 'has higher price with longer time to expiry' do
        short_term_price = described_class.calculate(
          spot_price: spot_price,
          strike_price: strike_price,
          time_to_expiry: 0.1, # 1.2 months
          risk_free_rate: risk_free_rate,
          volatility: volatility,
          option_type: OptionsTrader::CALL,
          steps: steps
        )

        long_term_price = described_class.calculate(
          spot_price: spot_price,
          strike_price: strike_price,
          time_to_expiry: 0.5, # 6 months
          risk_free_rate: risk_free_rate,
          volatility: volatility,
          option_type: OptionsTrader::CALL,
          steps: steps
        )

        expect(long_term_price).to be > short_term_price
      end
    end

    context 'with PUT options' do
      it 'returns a reasonable put option price' do
        price = described_class.calculate(
          spot_price: spot_price,
          strike_price: strike_price,
          time_to_expiry: time_to_expiry,
          risk_free_rate: risk_free_rate,
          volatility: volatility,
          option_type: OptionsTrader::PUT,
          steps: steps
        )

        expect(price).to be_a(Float)
        expect(price).to be > 0
        expect(price).to be < strike_price # Put price should be less than strike price
      end

      it 'prices in-the-money puts higher than out-of-the-money puts' do
        itm_price = described_class.calculate(
          spot_price: 95.0, # ITM: spot < strike
          strike_price: strike_price,
          time_to_expiry: time_to_expiry,
          risk_free_rate: risk_free_rate,
          volatility: volatility,
          option_type: OptionsTrader::PUT,
          steps: steps
        )

        otm_price = described_class.calculate(
          spot_price: 110.0, # OTM: spot > strike
          strike_price: strike_price,
          time_to_expiry: time_to_expiry,
          risk_free_rate: risk_free_rate,
          volatility: volatility,
          option_type: OptionsTrader::PUT,
          steps: steps
        )

        expect(itm_price).to be > otm_price
      end
    end

    context 'with different parameters' do
      it 'increases option price with higher volatility' do
        low_vol_price = described_class.calculate(
          spot_price: spot_price,
          strike_price: strike_price,
          time_to_expiry: time_to_expiry,
          risk_free_rate: risk_free_rate,
          volatility: 0.1, # 10% volatility
          option_type: OptionsTrader::CALL,
          steps: steps
        )

        high_vol_price = described_class.calculate(
          spot_price: spot_price,
          strike_price: strike_price,
          time_to_expiry: time_to_expiry,
          risk_free_rate: risk_free_rate,
          volatility: 0.4, # 40% volatility
          option_type: OptionsTrader::CALL,
          steps: steps
        )

        expect(high_vol_price).to be > low_vol_price
      end

      it 'handles dividend yield parameter' do
        price_without_dividend = described_class.calculate(
          spot_price: spot_price,
          strike_price: strike_price,
          time_to_expiry: time_to_expiry,
          risk_free_rate: risk_free_rate,
          volatility: volatility,
          option_type: OptionsTrader::CALL,
          steps: steps,
          dividend_yield: 0.0
        )

        price_with_dividend = described_class.calculate(
          spot_price: spot_price,
          strike_price: strike_price,
          time_to_expiry: time_to_expiry,
          risk_free_rate: risk_free_rate,
          volatility: volatility,
          option_type: OptionsTrader::CALL,
          steps: steps,
          dividend_yield: 0.02 # 2% dividend yield
        )

        # Call price should be lower with dividend yield
        expect(price_with_dividend).to be < price_without_dividend
      end

      it 'uses default daily steps when steps parameter is nil' do
        price_default_steps = described_class.calculate(
          spot_price: spot_price,
          strike_price: strike_price,
          time_to_expiry: time_to_expiry,
          risk_free_rate: risk_free_rate,
          volatility: volatility,
          option_type: OptionsTrader::CALL
          # steps parameter omitted
        )

        price_explicit_steps = described_class.calculate(
          spot_price: spot_price,
          strike_price: strike_price,
          time_to_expiry: time_to_expiry,
          risk_free_rate: risk_free_rate,
          volatility: volatility,
          option_type: OptionsTrader::CALL,
          steps: (time_to_expiry * 252).round # Should match default calculation
        )

        expect(price_default_steps).to be_within(0.01).of(price_explicit_steps)
      end
    end

    context 'with edge cases and validation' do
      it 'raises error for invalid option type' do
        expect {
          described_class.calculate(
            spot_price: spot_price,
            strike_price: strike_price,
            time_to_expiry: time_to_expiry,
            risk_free_rate: risk_free_rate,
            volatility: volatility,
            option_type: 'INVALID',
            steps: steps
          )
        }.to raise_error(ArgumentError, /option_type must be CALL or PUT/)
      end

      it 'handles at-the-money options' do
        atm_call_price = described_class.calculate(
          spot_price: 100.0,
          strike_price: 100.0, # ATM
          time_to_expiry: time_to_expiry,
          risk_free_rate: risk_free_rate,
          volatility: volatility,
          option_type: OptionsTrader::CALL,
          steps: steps
        )

        atm_put_price = described_class.calculate(
          spot_price: 100.0,
          strike_price: 100.0, # ATM
          time_to_expiry: time_to_expiry,
          risk_free_rate: risk_free_rate,
          volatility: volatility,
          option_type: OptionsTrader::PUT,
          steps: steps
        )

        expect(atm_call_price).to be > 0
        expect(atm_put_price).to be > 0
        # Put-call parity: C - P H S - K*e^(-rT) (approximately for ATM)
        expect(atm_call_price).to be > atm_put_price # Call should be slightly higher due to interest rate
      end

      it 'handles very short time to expiry' do
        price = described_class.calculate(
          spot_price: spot_price,
          strike_price: strike_price,
          time_to_expiry: 0.001, # Very short time
          risk_free_rate: risk_free_rate,
          volatility: volatility,
          option_type: OptionsTrader::CALL,
          steps: 5 # Few steps for short time
        )

        expect(price).to be_a(Float)
        expect(price).to be >= 0
      end

      it 'ensures minimum of 1 step even for very short times' do
        # This tests the [1, (time_to_expiry * 252).round].max logic
        price = described_class.calculate(
          spot_price: spot_price,
          strike_price: strike_price,
          time_to_expiry: 0.0001, # Extremely short time
          risk_free_rate: risk_free_rate,
          volatility: volatility,
          option_type: OptionsTrader::CALL
          # Let it use default steps calculation
        )

        expect(price).to be_a(Float)
        expect(price).to be >= 0
      end
    end

    context 'theoretical properties' do
      it 'satisfies intrinsic value lower bound for ITM call' do
        itm_spot = 120.0
        intrinsic_value = itm_spot - strike_price

        option_price = described_class.calculate(
          spot_price: itm_spot,
          strike_price: strike_price,
          time_to_expiry: time_to_expiry,
          risk_free_rate: risk_free_rate,
          volatility: volatility,
          option_type: OptionsTrader::CALL,
          steps: steps
        )

        # Option price should be at least the intrinsic value
        expect(option_price).to be >= intrinsic_value
      end

      it 'satisfies theoretical lower bound for ITM put' do
        itm_spot = 80.0
        intrinsic_value = strike_price - itm_spot
        # For European puts, the theoretical lower bound is max(0, K*e^(-rT) - S)
        theoretical_lower_bound = [0, strike_price * Math.exp(-risk_free_rate * time_to_expiry) - itm_spot].max

        option_price = described_class.calculate(
          spot_price: itm_spot,
          strike_price: strike_price,
          time_to_expiry: time_to_expiry,
          risk_free_rate: risk_free_rate,
          volatility: volatility,
          option_type: OptionsTrader::PUT,
          steps: steps
        )

        # Option price should be at least the theoretical lower bound for European options
        expect(option_price).to be >= theoretical_lower_bound
        # And should be positive for ITM options
        expect(option_price).to be > 0
      end
    end
  end
end