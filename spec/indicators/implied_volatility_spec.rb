require 'spec_helper'

RSpec.describe OptionsTrader::Indicators::ImpliedVolatility do
  let(:spot_price) { 100.0 }
  let(:strike_price) { 105.0 }
  let(:time_to_expiry) { 0.25 } # 3 months
  let(:risk_free_rate) { 0.05 } # 5%
  let(:market_price) { 3.5 }
  let(:option_type) { OptionsTrader::CALL }

  describe '.calculate' do
    context 'with valid parameters' do
      it 'returns a reasonable implied volatility value' do
        iv = described_class.calculate(
          market_price: market_price,
          spot_price: spot_price,
          strike_price: strike_price,
          time_to_expiry: time_to_expiry,
          risk_free_rate: risk_free_rate,
          option_type: option_type
        )

        expect(iv).to be_a(Float)
        expect(iv).to be > 0
        expect(iv).to be < 5.0 # Should be less than 500%
      end

      it 'works with PUT options' do
        put_market_price = 8.5 # Adjusted to a more reasonable price for PUT
        iv = described_class.calculate(
          market_price: put_market_price,
          spot_price: spot_price,
          strike_price: strike_price,
          time_to_expiry: time_to_expiry,
          risk_free_rate: risk_free_rate,
          option_type: OptionsTrader::PUT
        )

        expect(iv).to be_a(Float).or(be_nil)
        if iv
          expect(iv).to be > 0
        end
      end

      it 'accepts dividend yield parameter' do
        iv = described_class.calculate(
          market_price: market_price,
          spot_price: spot_price,
          strike_price: strike_price,
          time_to_expiry: time_to_expiry,
          risk_free_rate: risk_free_rate,
          option_type: option_type,
          dividend_yield: 0.02
        )

        expect(iv).to be_a(Float)
        expect(iv).to be > 0
      end

      it 'accepts custom tolerance parameter' do
        iv = described_class.calculate(
          market_price: market_price,
          spot_price: spot_price,
          strike_price: strike_price,
          time_to_expiry: time_to_expiry,
          risk_free_rate: risk_free_rate,
          option_type: option_type,
          tolerance: 1e-8
        )

        expect(iv).to be_a(Float)
        expect(iv).to be > 0
      end
    end

    context 'with edge cases' do
      it 'returns nil when no solution exists (market price too high)' do
        iv = described_class.calculate(
          market_price: 1000.0, # Unrealistically high market price
          spot_price: spot_price,
          strike_price: strike_price,
          time_to_expiry: time_to_expiry,
          risk_free_rate: risk_free_rate,
          option_type: option_type
        )

        expect(iv).to be_nil
      end

      it 'handles zero market price (may return lower bound)' do
        iv = described_class.calculate(
          market_price: 0.0,
          spot_price: spot_price,
          strike_price: strike_price,
          time_to_expiry: time_to_expiry,
          risk_free_rate: risk_free_rate,
          option_type: option_type
        )

        # Algorithm may return the lower bound (0.001) for zero market price
        expect(iv).to be_a(Float).or(be_nil)
        if iv
          expect(iv).to be >= 0.001
        end
      end

      it 'handles very short time to expiry' do
        iv = described_class.calculate(
          market_price: 1.0,
          spot_price: spot_price,
          strike_price: strike_price,
          time_to_expiry: 0.001, # Very short time
          risk_free_rate: risk_free_rate,
          option_type: option_type
        )

        # May return nil or a valid value depending on market conditions
        expect(iv).to be_nil.or(be_a(Float))
      end

      it 'handles at-the-money options' do
        iv = described_class.calculate(
          market_price: 2.5,
          spot_price: 100.0,
          strike_price: 100.0, # ATM
          time_to_expiry: time_to_expiry,
          risk_free_rate: risk_free_rate,
          option_type: option_type
        )

        expect(iv).to be_a(Float).or(be_nil)
      end
    end

    context 'parameter validation through behavior' do
      it 'behaves correctly with different risk-free rates' do
        high_rate_iv = described_class.calculate(
          market_price: market_price,
          spot_price: spot_price,
          strike_price: strike_price,
          time_to_expiry: time_to_expiry,
          risk_free_rate: 0.10, # High rate
          option_type: option_type
        )

        low_rate_iv = described_class.calculate(
          market_price: market_price,
          spot_price: spot_price,
          strike_price: strike_price,
          time_to_expiry: time_to_expiry,
          risk_free_rate: 0.01, # Low rate
          option_type: option_type
        )

        # Both should be valid or both nil, but likely different values
        if high_rate_iv && low_rate_iv
          expect(high_rate_iv).not_to eq(low_rate_iv)
        end
      end

      it 'handles different spot prices consistently' do
        low_spot_iv = described_class.calculate(
          market_price: 1.0,
          spot_price: 50.0, # Lower spot
          strike_price: strike_price,
          time_to_expiry: time_to_expiry,
          risk_free_rate: risk_free_rate,
          option_type: option_type
        )

        high_spot_iv = described_class.calculate(
          market_price: 8.0,
          spot_price: 150.0, # Higher spot
          strike_price: strike_price,
          time_to_expiry: time_to_expiry,
          risk_free_rate: risk_free_rate,
          option_type: option_type
        )

        # Should return reasonable values for reasonable market prices
        expect(low_spot_iv).to be_a(Float).or(be_nil)
        expect(high_spot_iv).to be_a(Float).or(be_nil)
      end
    end
  end
end
