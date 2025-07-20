# frozen_string_literal: true

require 'spec_helper'

RSpec.describe OptionsTrader::CallSpread do
  let(:short_leg) do
    double('CallOption',
      symbol: 'SPY250620C00500000',
      strike: 500.0,
      mark: 3.50,
      delta: 0.30,
      expiration_date: Date.new(2025, 6, 20),
      market_change?: false,
      check_market: nil
    )
  end

  let(:long_leg) do
    double('CallOption',
      symbol: 'SPY250620C00510000',
      strike: 510.0,
      mark: 2.00,
      delta: 0.20,
      expiration_date: Date.new(2025, 6, 20),
      market_change?: false,
      check_market: nil
    )
  end

  let(:call_spread) do
    described_class.new(
      underlying_symbol: 'SPY',
      short_leg: short_leg,
      long_leg: long_leg,
      quantity: 2
    )
  end

  describe '#initialize' do
    it 'sets all attributes' do
      expect(call_spread.underlying_symbol).to eq('SPY')
      expect(call_spread.short_leg).to eq(short_leg)
      expect(call_spread.long_leg).to eq(long_leg)
      expect(call_spread.quantity).to eq(2)
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
  end

  describe '#expiration_date' do
    it 'returns short leg expiration date' do
      expect(call_spread.expiration_date).to eq(Date.new(2025, 6, 20))
    end
  end

  describe '#delta' do
    it 'returns short leg delta' do
      expect(call_spread.delta).to eq(0.30)
    end
  end

  describe '#credit' do
    it 'calculates credit as short mark minus long mark' do
      expect(call_spread.credit).to eq(1.50) # 3.50 - 2.00
    end

    it 'rounds to nearest increment' do
      allow(short_leg).to receive(:mark).and_return(3.53)
      allow(long_leg).to receive(:mark).and_return(2.02)

      expect(call_spread.credit).to eq(1.51) # 3.53 - 2.02
    end
  end

  describe '#debit' do
    it 'calculates debit as long mark minus short mark' do
      expect(call_spread.debit).to eq(-1.50) # 2.00 - 3.50
    end
  end

  describe '#spread_width' do
    it 'calculates absolute difference between strikes' do
      expect(call_spread.spread_width).to eq(10.0) # |510.0 - 500.0|
    end

    it 'caches the result' do
      # First call
      expect(call_spread.spread_width).to eq(10.0)

      # Change the strike values
      allow(long_leg).to receive(:strike).and_return(520.0)

      # Should return cached value
      expect(call_spread.spread_width).to eq(10.0)
    end
  end

  describe '#symbols' do
    it 'returns array of leg symbols' do
      expect(call_spread.symbols).to eq(['SPY250620C00500000', 'SPY250620C00510000'])
    end
  end

  describe '#strikes' do
    it 'returns array of leg strikes' do
      expect(call_spread.strikes).to eq([500.0, 510.0])
    end
  end

  describe '#marks' do
    it 'returns array of leg marks' do
      expect(call_spread.marks).to eq([3.50, 2.00])
    end
  end

  describe '#market_change?' do
    it 'returns true if either leg has market change' do
      allow(short_leg).to receive(:market_change?).and_return(true)
      allow(long_leg).to receive(:market_change?).and_return(false)

      expect(call_spread.market_change?).to be true
    end

    it 'returns true if long leg has market change' do
      allow(short_leg).to receive(:market_change?).and_return(false)
      allow(long_leg).to receive(:market_change?).and_return(true)

      expect(call_spread.market_change?).to be true
    end

    it 'returns false if neither leg has market change' do
      allow(short_leg).to receive(:market_change?).and_return(false)
      allow(long_leg).to receive(:market_change?).and_return(false)

      expect(call_spread.market_change?).to be false
    end
  end

  describe '#check_market' do
    it 'calls check_market on both legs using threads' do
      expect(short_leg).to receive(:check_market)
      expect(long_leg).to receive(:check_market)

      call_spread.check_market
    end
  end

  describe '#to_s' do
    it 'returns formatted string representation' do
      expected = "<OptionsTrader::CallSpread #{Date.new(2025, 6, 20)}, " \
                 "SPY250620C00500000, 500.0, " \
                 "SPY250620C00510000, 510.0>"

      expect(call_spread.to_s).to eq(expected)
    end
  end

  describe '#to_h' do
    let(:short_leg) do
      double('CallOption',
        symbol: 'SPY250620C00500000',
        strike: 500.0,
        mark: 3.50,
        delta: 0.30,
        ask: 3.55,
        bid: 3.45,
        expiration_date: Date.new(2025, 6, 20),
        open_interest: 1500,
        market_change?: false,
        check_market: nil
      )
    end

    let(:long_leg) do
      double('CallOption',
        symbol: 'SPY250620C00510000',
        strike: 510.0,
        mark: 2.00,
        delta: 0.20,
        ask: 2.05,
        bid: 1.95,
        expiration_date: Date.new(2025, 6, 20),
        open_interest: 800,
        market_change?: false,
        check_market: nil
      )
    end

    it 'returns hash representation with all attributes' do
      result = call_spread.to_h

      expect(result).to be_a(Hash)
      expect(result[:type]).to eq('callspread')
      expect(result[:quantity]).to eq(2)
      expect(result[:underlying_symbol]).to eq('SPY')
      expect(result[:round]).to eq(2)
      expect(result[:increment]).to eq(0.01)
    end

    it 'includes short_leg details' do
      result = call_spread.to_h

      expect(result[:short_leg]).to eq({
        symbol: 'SPY250620C00500000',
        strike: 500.0,
        delta: 0.30,
        mark: 3.50,
        ask: 3.55,
        bid: 3.45,
        expiration_date: Date.new(2025, 6, 20),
        open_interest: 1500
      })
    end

    it 'includes long_leg details' do
      result = call_spread.to_h

      expect(result[:long_leg]).to eq({
        symbol: 'SPY250620C00510000',
        strike: 510.0,
        delta: 0.20,
        mark: 2.00,
        ask: 2.05,
        bid: 1.95,
        expiration_date: Date.new(2025, 6, 20),
        open_interest: 800
      })
    end


  end

  describe 'inheritance' do
    it 'inherits from StrategyBase' do
      expect(call_spread).to be_a(OptionsTrader::StrategyBase)
    end
  end

  describe 'serialization' do
    let(:short_leg_with_all_attrs) do
      double('CallOption',
        symbol: 'SPY250620C00500000',
        strike: 500.0,
        mark: 3.50,
        delta: 0.30,
        ask: 3.55,
        bid: 3.45,
        expiration_date: Date.new(2025, 6, 20),
        open_interest: 1500,
        market_change?: false,
        check_market: nil
      )
    end

    let(:long_leg_with_all_attrs) do
      double('CallOption',
        symbol: 'SPY250620C00510000',
        strike: 510.0,
        mark: 2.00,
        delta: 0.20,
        ask: 2.05,
        bid: 1.95,
        expiration_date: Date.new(2025, 6, 20),
        open_interest: 800,
        market_change?: false,
        check_market: nil
      )
    end

    let(:call_spread_for_serialization) do
      described_class.new(
        underlying_symbol: 'SPY',
        short_leg: short_leg_with_all_attrs,
        long_leg: long_leg_with_all_attrs,
        quantity: 2
      )
    end

    let(:call_spread_hash) do
      {
        type: 'callspread',
        quantity: 3,
        underlying_symbol: 'SPY',
        round: 2,
        increment: 0.01,
        short_leg: {
          symbol: 'SPY250620C00500000',
          strike: 500.0,
          delta: 0.30,
          mark: 3.50,
          ask: 3.55,
          bid: 3.45,
          expiration_date: Date.new(2025, 6, 20),
          open_interest: 1500
        },
        long_leg: {
          symbol: 'SPY250620C00510000',
          strike: 510.0,
          delta: 0.20,
          mark: 2.00,
          ask: 2.05,
          bid: 1.95,
          expiration_date: Date.new(2025, 6, 20),
          open_interest: 800
        }
      }
    end

    describe '#to_json' do
      it 'converts to JSON string' do
        json_string = call_spread_for_serialization.to_json
        expect(json_string).to be_a(String)

        parsed = JSON.parse(json_string, symbolize_names: true)
        expect(parsed[:type]).to eq('callspread')
        expect(parsed[:underlying_symbol]).to eq('SPY')
      end
    end

    describe '.from_h' do
      it 'reconstructs CallSpread from hash' do
        spread = described_class.from_h(call_spread_hash)

        expect(spread).to be_a(OptionsTrader::CallSpread)
        expect(spread.underlying_symbol).to eq('SPY')
        expect(spread.quantity).to eq(3)
        expect(spread.increment).to eq(0.01)
        expect(spread.round).to eq(2)
      end

      it 'reconstructs option legs from hash data' do
        spread = described_class.from_h(call_spread_hash)

        expect(spread.short_leg).to be_a(OptionsTrader::CallOption)
        expect(spread.short_leg.symbol).to eq('SPY250620C00500000')
        expect(spread.short_leg.strike).to eq(500.0)
        expect(spread.short_leg.mark).to eq(3.50)

        expect(spread.long_leg).to be_a(OptionsTrader::CallOption)
        expect(spread.long_leg.symbol).to eq('SPY250620C00510000')
        expect(spread.long_leg.strike).to eq(510.0)
        expect(spread.long_leg.mark).to eq(2.00)
      end


    end

    describe '.from_json' do
      it 'reconstructs CallSpread from JSON string' do
        json_string = call_spread_hash.to_json
        spread = described_class.from_json(json_string)

        expect(spread).to be_a(OptionsTrader::CallSpread)
        expect(spread.underlying_symbol).to eq('SPY')
        expect(spread.quantity).to eq(3)
      end

      it 'round-trip serialization preserves data' do
        # Test with actual spread that has both legs
        json_string = call_spread_for_serialization.to_json
        reconstructed = described_class.from_json(json_string)

        expect(reconstructed.underlying_symbol).to eq('SPY')
        expect(reconstructed.quantity).to eq(2)
        expect(reconstructed.increment).to eq(0.01)
        expect(reconstructed.round).to eq(2)
      end
    end
  end

  describe '#extract_kwargs' do
    it 'returns correct kwargs for :open instruction' do
      allow(call_spread).to receive(:strategy_price).with(:open).and_return(1.50)
      
      kwargs = call_spread.extract_kwargs(:open)
      
      expect(kwargs).to eq({
        strategy_type: 'callspread',
        short_leg_symbol: 'SPY250620C00500000',
        long_leg_symbol: 'SPY250620C00510000',
        price: 1.50,
        quantiy: 2  # Note: keeping typo from original
      })
    end

    it 'returns correct kwargs for :exit instruction' do
      allow(call_spread).to receive(:strategy_price).with(:exit).and_return(0.75)
      
      kwargs = call_spread.extract_kwargs(:exit)
      
      expect(kwargs).to eq({
        strategy_type: 'callspread',
        short_leg_symbol: 'SPY250620C00500000',
        long_leg_symbol: 'SPY250620C00510000',
        price: 0.75,
        quantiy: 2  # Note: keeping typo from original
      })
    end
  end
end