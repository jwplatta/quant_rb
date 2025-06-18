# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Platypi::CallSpread do
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

  before do
    allow(call_spread).to receive(:initialize_orderable)
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
      allow(spread).to receive(:initialize_orderable)

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

  describe '#instruments' do
    it 'returns array of instrument hashes' do
      instruments = call_spread.instruments

      expect(instruments).to eq([
        {
          symbol: 'SPY250620C00500000',
          long_short: 'SHORT',
          put_call: 'CALL'
        },
        {
          symbol: 'SPY250620C00510000',
          long_short: 'LONG',
          put_call: 'CALL'
        }
      ])
    end
  end

  describe '#to_s' do
    it 'returns formatted string representation' do
      expected = "<Platypi::CallSpread #{Date.new(2025, 6, 20)}, " \
                 "SPY250620C00500000, 500.0, " \
                 "SPY250620C00510000, 510.0>"

      expect(call_spread.to_s).to eq(expected)
    end
  end

  describe 'inheritance' do
    it 'inherits from StrategyBase' do
      expect(call_spread).to be_a(Platypi::StrategyBase)
    end
  end
end