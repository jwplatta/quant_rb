# frozen_string_literal: true

require 'spec_helper'

RSpec.describe OptionsTrader::PutSpread do
  let(:short_leg) do
    double('PutOption',
      symbol: 'SPY250620P00450000',
      strike: 450.0,
      mark: 2.75,
      delta: -0.25,
      expiration_date: Date.new(2025, 6, 20),
      market_change?: false,
      check_market: nil
    )
  end

  let(:long_leg) do
    double('PutOption',
      symbol: 'SPY250620P00440000',
      strike: 440.0,
      mark: 1.50,
      delta: -0.15,
      expiration_date: Date.new(2025, 6, 20),
      market_change?: false,
      check_market: nil
    )
  end

  let(:put_spread) do
    described_class.new(
      underlying_symbol: 'SPY',
      short_leg: short_leg,
      long_leg: long_leg,
      quantity: 3
    )
  end

  describe '#initialize' do
    it 'sets all attributes' do
      expect(put_spread.underlying_symbol).to eq('SPY')
      expect(put_spread.short_leg).to eq(short_leg)
      expect(put_spread.long_leg).to eq(long_leg)
      expect(put_spread.quantity).to eq(3)
    end

    it 'uses default values' do
      spread = described_class.new

      expect(spread.underlying_symbol).to be_nil
      expect(spread.short_leg).to be_nil
      expect(spread.long_leg).to be_nil
      expect(spread.quantity).to eq(1)
      expect(spread.increment).to eq(0.01)
      expect(spread.round).to eq(2)
    end

    it 'accepts custom increment and round values' do
      spread = described_class.new(increment: 0.05, round: 3)

      expect(spread.increment).to eq(0.05)
      expect(spread.round).to eq(3)
    end
  end

  describe '#expiration_date' do
    it 'returns short leg expiration date' do
      expect(put_spread.expiration_date).to eq(Date.new(2025, 6, 20))
    end

    it 'caches the expiration date' do
      # First call
      expect(put_spread.expiration_date).to eq(Date.new(2025, 6, 20))

      # Change the expiration date on short leg
      allow(short_leg).to receive(:expiration_date).and_return(Date.new(2025, 7, 20))

      # Should return cached value
      expect(put_spread.expiration_date).to eq(Date.new(2025, 6, 20))
    end
  end

  describe '#delta' do
    it 'returns short leg delta' do
      expect(put_spread.delta).to eq(0.25)
    end
  end

  describe '#credit' do
    it 'calculates credit as short mark minus long mark' do
      expect(put_spread.credit).to eq(1.25) # 2.75 - 1.50
    end

    it 'rounds to nearest increment' do
      allow(short_leg).to receive(:mark).and_return(2.73)
      allow(long_leg).to receive(:mark).and_return(1.52)

      expect(put_spread.credit).to eq(1.21) # 2.73 - 1.52
    end

    it 'handles negative credit' do
      allow(short_leg).to receive(:mark).and_return(1.00)
      allow(long_leg).to receive(:mark).and_return(2.00)

      expect(put_spread.credit).to eq(-1.00) # 1.00 - 2.00
    end
  end

  describe '#debit' do
    it 'calculates debit as long mark minus short mark' do
      expect(put_spread.debit).to eq(-1.25) # 1.50 - 2.75
    end

    it 'handles positive debit when long is more expensive' do
      allow(short_leg).to receive(:mark).and_return(1.00)
      allow(long_leg).to receive(:mark).and_return(2.00)

      expect(put_spread.debit).to eq(1.00) # 2.00 - 1.00
    end
  end

  describe '#spread_width' do
    it 'calculates absolute difference between strikes' do
      expect(put_spread.spread_width).to eq(10.0) # |440.0 - 450.0|
    end

    it 'caches the result' do
      # First call
      expect(put_spread.spread_width).to eq(10.0)

      # Change the strike values
      allow(long_leg).to receive(:strike).and_return(430.0)

      # Should return cached value
      expect(put_spread.spread_width).to eq(10.0)
    end

    it 'handles different strike ordering' do
      # Create spread where long strike > short strike
      allow(short_leg).to receive(:strike).and_return(440.0)
      allow(long_leg).to receive(:strike).and_return(450.0)

      spread = described_class.new(short_leg: short_leg, long_leg: long_leg)
      expect(spread.spread_width).to eq(10.0) # |450.0 - 440.0|
    end
  end

  describe '#symbols' do
    it 'returns array of leg symbols' do
      expect(put_spread.symbols).to eq(['SPY250620P00450000', 'SPY250620P00440000'])
    end
  end

  describe '#strikes' do
    it 'returns array of leg strikes' do
      expect(put_spread.strikes).to eq([450.0, 440.0])
    end
  end

  describe '#marks' do
    it 'returns array of leg marks' do
      expect(put_spread.marks).to eq([2.75, 1.50])
    end
  end

  describe '#market_change?' do
    it 'returns true if short leg has market change' do
      allow(short_leg).to receive(:market_change?).and_return(true)
      allow(long_leg).to receive(:market_change?).and_return(false)

      expect(put_spread.market_change?).to be true
    end

    it 'returns true if long leg has market change' do
      allow(short_leg).to receive(:market_change?).and_return(false)
      allow(long_leg).to receive(:market_change?).and_return(true)

      expect(put_spread.market_change?).to be true
    end

    it 'returns true if both legs have market change' do
      allow(short_leg).to receive(:market_change?).and_return(true)
      allow(long_leg).to receive(:market_change?).and_return(true)

      expect(put_spread.market_change?).to be true
    end

    it 'returns false if neither leg has market change' do
      allow(short_leg).to receive(:market_change?).and_return(false)
      allow(long_leg).to receive(:market_change?).and_return(false)

      expect(put_spread.market_change?).to be false
    end
  end

  describe '#check_market' do
    it 'calls check_market on both legs using threads' do
      expect(short_leg).to receive(:check_market)
      expect(long_leg).to receive(:check_market)

      put_spread.check_market
    end

    it 'waits for both threads to complete' do
      short_called = false
      long_called = false

      allow(short_leg).to receive(:check_market) do
        sleep(0.01)
        short_called = true
      end

      allow(long_leg).to receive(:check_market) do
        sleep(0.01)
        long_called = true
      end

      put_spread.check_market

      expect(short_called).to be true
      expect(long_called).to be true
    end
  end

  describe '#to_s' do
    it 'returns formatted string representation' do
      expected = "<OptionsTrader::PutSpread #{Date.new(2025, 6, 20)}, " \
                 "SPY250620P00450000, 450.0, " \
                 "SPY250620P00440000, 440.0>"

      expect(put_spread.to_s).to eq(expected)
    end
  end

  describe '#to_h' do
    let(:short_leg) do
      double('PutOption',
        symbol: 'SPY250620P00450000',
        strike: 450.0,
        mark: 2.75,
        delta: -0.25,
        ask: 2.80,
        bid: 2.70,
        expiration_date: Date.new(2025, 6, 20),
        open_interest: 1200,
        market_change?: false,
        check_market: nil
      )
    end

    let(:long_leg) do
      double('PutOption',
        symbol: 'SPY250620P00440000',
        strike: 440.0,
        mark: 1.50,
        delta: -0.15,
        ask: 1.55,
        bid: 1.45,
        expiration_date: Date.new(2025, 6, 20),
        open_interest: 900,
        market_change?: false,
        check_market: nil
      )
    end

    it 'returns hash representation with all attributes' do
      result = put_spread.to_h

      expect(result).to be_a(Hash)
      expect(result[:type]).to eq('putspread')
      expect(result[:quantity]).to eq(3)
      expect(result[:underlying_symbol]).to eq('SPY')
      expect(result[:round]).to eq(2)
      expect(result[:increment]).to eq(0.01)
    end

    it 'includes short_leg details' do
      result = put_spread.to_h

      expect(result[:short_leg]).to eq({
        symbol: 'SPY250620P00450000',
        strike: 450.0,
        delta: -0.25,
        mark: 2.75,
        ask: 2.80,
        bid: 2.70,
        expiration_date: Date.new(2025, 6, 20),
        open_interest: 1200
      })
    end

    it 'includes long_leg details' do
      result = put_spread.to_h

      expect(result[:long_leg]).to eq({
        symbol: 'SPY250620P00440000',
        strike: 440.0,
        delta: -0.15,
        mark: 1.50,
        ask: 1.55,
        bid: 1.45,
        expiration_date: Date.new(2025, 6, 20),
        open_interest: 900
      })
    end


  end

  describe 'inheritance' do
    it 'inherits from StrategyBase' do
      expect(put_spread).to be_a(OptionsTrader::StrategyBase)
    end

    it 'responds to StrategyBase methods' do
      expect(put_spread).to respond_to(:type)
      expect(put_spread).to respond_to(:nearest_increment)
      expect(put_spread).to respond_to(:increment)
      expect(put_spread).to respond_to(:round)
    end
  end

  describe 'serialization' do
    let(:short_leg_with_all_attrs) do
      double('PutOption',
        symbol: 'SPY250620P00450000',
        strike: 450.0,
        mark: 2.75,
        delta: -0.25,
        ask: 2.80,
        bid: 2.70,
        expiration_date: Date.new(2025, 6, 20),
        open_interest: 1200,
        market_change?: false,
        check_market: nil
      )
    end

    let(:long_leg_with_all_attrs) do
      double('PutOption',
        symbol: 'SPY250620P00440000',
        strike: 440.0,
        mark: 1.50,
        delta: -0.15,
        ask: 1.55,
        bid: 1.45,
        expiration_date: Date.new(2025, 6, 20),
        open_interest: 900,
        market_change?: false,
        check_market: nil
      )
    end

    let(:put_spread_for_serialization) do
      described_class.new(
        underlying_symbol: 'SPY',
        short_leg: short_leg_with_all_attrs,
        long_leg: long_leg_with_all_attrs,
        quantity: 3
      )
    end

    let(:put_spread_hash) do
      {
        type: 'putspread',
        quantity: 2,
        underlying_symbol: 'SPY',
        round: 2,
        increment: 0.01,
        short_leg: {
          symbol: 'SPY250620P00450000',
          strike: 450.0,
          delta: -0.25,
          mark: 2.75,
          ask: 2.80,
          bid: 2.70,
          expiration_date: Date.new(2025, 6, 20),
          open_interest: 1200
        },
        long_leg: {
          symbol: 'SPY250620P00440000',
          strike: 440.0,
          delta: -0.15,
          mark: 1.50,
          ask: 1.55,
          bid: 1.45,
          expiration_date: Date.new(2025, 6, 20),
          open_interest: 900
        }
      }
    end

    describe '#to_json' do
      it 'converts to JSON string' do
        json_string = put_spread_for_serialization.to_json
        expect(json_string).to be_a(String)

        parsed = JSON.parse(json_string, symbolize_names: true)
        expect(parsed[:type]).to eq('putspread')
        expect(parsed[:underlying_symbol]).to eq('SPY')
      end
    end

    describe '.from_h' do
      it 'reconstructs PutSpread from hash' do
        spread = described_class.from_h(put_spread_hash)

        expect(spread).to be_a(OptionsTrader::PutSpread)
        expect(spread.underlying_symbol).to eq('SPY')
        expect(spread.quantity).to eq(2)
        expect(spread.increment).to eq(0.01)
        expect(spread.round).to eq(2)
      end

      it 'reconstructs option legs from hash data' do
        spread = described_class.from_h(put_spread_hash)

        expect(spread.short_leg).to be_a(OptionsTrader::PutOption)
        expect(spread.short_leg.symbol).to eq('SPY250620P00450000')
        expect(spread.short_leg.strike).to eq(450.0)
        expect(spread.short_leg.mark).to eq(2.75)

        expect(spread.long_leg).to be_a(OptionsTrader::PutOption)
        expect(spread.long_leg.symbol).to eq('SPY250620P00440000')
        expect(spread.long_leg.strike).to eq(440.0)
        expect(spread.long_leg.mark).to eq(1.50)
      end


    end

    describe '.from_json' do
      it 'reconstructs PutSpread from JSON string' do
        json_string = put_spread_hash.to_json
        spread = described_class.from_json(json_string)

        expect(spread).to be_a(OptionsTrader::PutSpread)
        expect(spread.underlying_symbol).to eq('SPY')
        expect(spread.quantity).to eq(2)
      end

      it 'round-trip serialization preserves data' do
        # Test with actual spread that has both legs
        json_string = put_spread_for_serialization.to_json
        reconstructed = described_class.from_json(json_string)

        expect(reconstructed.underlying_symbol).to eq('SPY')
        expect(reconstructed.quantity).to eq(3)
        expect(reconstructed.increment).to eq(0.01)
        expect(reconstructed.round).to eq(2)
      end
    end
  end

  describe '#extract_kwargs' do
    let(:put_spread_for_kwargs) do
      described_class.new(
        underlying_symbol: 'SPY',
        short_leg: short_leg,
        long_leg: long_leg,
        quantity: 2
      )
    end

    it 'returns correct kwargs for :open instruction' do
      allow(put_spread_for_kwargs).to receive(:strategy_price).with(:open).and_return(1.25)

      kwargs = put_spread_for_kwargs.extract_kwargs(:open)

      expect(kwargs).to eq({
        strategy_type: 'putspread',
        short_leg_symbol: 'SPY250620P00450000',
        long_leg_symbol: 'SPY250620P00440000',
        price: 1.25,
        quantity: 2
      })
    end

    it 'returns correct kwargs for :exit instruction' do
      allow(put_spread_for_kwargs).to receive(:strategy_price).with(:exit).and_return(0.60)

      kwargs = put_spread_for_kwargs.extract_kwargs(:exit)

      expect(kwargs).to eq({
        strategy_type: 'putspread',
        short_leg_symbol: 'SPY250620P00450000',
        long_leg_symbol: 'SPY250620P00440000',
        price: 0.60,
        quantity: 2
      })
    end
  end
end