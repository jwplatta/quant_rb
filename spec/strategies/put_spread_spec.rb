# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Platypi::PutSpread do
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

  before do
    allow(put_spread).to receive(:initialize_orderable)
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
      allow(spread).to receive(:initialize_orderable)

      expect(spread.underlying_symbol).to be_nil
      expect(spread.short_leg).to be_nil
      expect(spread.long_leg).to be_nil
      expect(spread.quantity).to eq(1)
      expect(spread.increment).to eq(0.01)
      expect(spread.round).to eq(2)
    end

    it 'accepts custom increment and round values' do
      spread = described_class.new(increment: 0.05, round: 3)
      allow(spread).to receive(:initialize_orderable)

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
      expect(put_spread.delta).to eq(-0.25)
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
      allow(spread).to receive(:initialize_orderable)

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

  describe '#instruments' do
    it 'returns array of instrument hashes for put spread' do
      instruments = put_spread.instruments

      expect(instruments).to eq([
        {
          symbol: 'SPY250620P00450000',
          long_short: 'SHORT',
          put_call: 'PUT'
        },
        {
          symbol: 'SPY250620P00440000',
          long_short: 'LONG',
          put_call: 'PUT'
        }
      ])
    end
  end

  describe '#to_event' do
    before do
      put_spread.trade_id = 'put_spread_123'
      allow(put_spread).to receive_messages(
        order_id: 'order_456',
        order_instruction: 'SELL_TO_OPEN',
        order_price: 125.00,
        order_fees: 2.50,
        order_commission: 1.50,
        instruments: [
          { symbol: 'SPY250620P00450000', long_short: 'SHORT', put_call: 'PUT' },
          { symbol: 'SPY250620P00440000', long_short: 'LONG', put_call: 'PUT' }
        ]
      )
    end

    it 'returns event hash with put spread data' do
      event = put_spread.to_event('OPEN')

      expect(event[:trade_id]).to eq('put_spread_123')
      expect(event[:trade_event]).to eq('OPEN')
      expect(event[:trade_type]).to eq('putspread')
      expect(event[:underlying_symbol]).to eq('SPY')
      expect(event[:order_id]).to eq('order_456')
      expect(event[:order_instruction]).to eq('SELL_TO_OPEN')
      expect(event[:price]).to eq(125.00)
      expect(event[:fees]).to eq(2.50)
      expect(event[:commission]).to eq(1.50)
      expect(event[:expiration_date]).to eq(Date.new(2025, 6, 20))
      expect(event[:quantity]).to eq(3)
      expect(event[:instruments]).to be_an(Array)
      expect(event[:timestamp]).to be_a(Time)
    end

    context 'when preview is true' do
      before do
        allow(put_spread).to receive_messages(
          order_preview_id: 'preview_789',
          order_preview_instruction: 'BUY_TO_CLOSE',
          order_preview_price: 120.00,
          order_preview_fees: 3.00,
          order_preview_commission: 2.00
        )
      end

      it 'uses preview values' do
        event = put_spread.to_event('CLOSE', preview: true)

        expect(event[:order_id]).to eq('preview_789')
        expect(event[:order_instruction]).to eq('BUY_TO_CLOSE')
        expect(event[:price]).to eq(120.00)
        expect(event[:fees]).to eq(3.00)
        expect(event[:commission]).to eq(2.00)
      end
    end
  end

  describe '#to_s' do
    it 'returns formatted string representation' do
      expected = "<Platypi::PutSpread #{Date.new(2025, 6, 20)}, " \
                 "SPY250620P00450000, 450.0, " \
                 "SPY250620P00440000, 440.0>"

      expect(put_spread.to_s).to eq(expected)
    end
  end

  describe 'inheritance' do
    it 'inherits from StrategyBase' do
      expect(put_spread).to be_a(Platypi::StrategyBase)
    end

    it 'responds to StrategyBase methods' do
      expect(put_spread).to respond_to(:type)
      expect(put_spread).to respond_to(:nearest_increment)
      expect(put_spread).to respond_to(:increment)
      expect(put_spread).to respond_to(:round)
    end
  end
end