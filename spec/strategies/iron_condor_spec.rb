# frozen_string_literal: true

require 'spec_helper'

RSpec.describe OptionsTrader::IronCondor do
  let(:put_spread) do
    double('PutSpread',
      delta: -0.15,
      credit: 1.25,
      debit: -1.25,
      symbols: ['SPY250620P00450000', 'SPY250620P00440000'],
      strikes: [450.0, 440.0],
      marks: [2.75, 1.50],
      spread_width: 10.0,
      market_change?: false,
      check_market: nil,
      expiration_date: Date.new(2025, 6, 20),
      short_leg: double('PutOption', symbol: 'SPY250620P00450000'),
      long_leg: double('PutOption', symbol: 'SPY250620P00440000'),
      instruments: [
        { symbol: 'SPY250620P00450000', long_short: 'SHORT', put_call: 'PUT' },
        { symbol: 'SPY250620P00440000', long_short: 'LONG', put_call: 'PUT' }
      ]
    )
  end

  let(:call_spread) do
    double('CallSpread',
      delta: 0.25,
      credit: 1.50,
      debit: -1.50,
      symbols: ['SPY250620C00500000', 'SPY250620C00510000'],
      strikes: [500.0, 510.0],
      marks: [3.50, 2.00],
      spread_width: 10.0,
      market_change?: false,
      check_market: nil,
      expiration_date: Date.new(2025, 6, 20),
      short_leg: double('CallOption', symbol: 'SPY250620C00500000'),
      long_leg: double('CallOption', symbol: 'SPY250620C00510000'),
      instruments: [
        { symbol: 'SPY250620C00500000', long_short: 'SHORT', put_call: 'CALL' },
        { symbol: 'SPY250620C00510000', long_short: 'LONG', put_call: 'CALL' }
      ]
    )
  end

  let(:iron_condor) do
    described_class.new(
      underlying_symbol: 'SPY',
      call_spread: call_spread,
      put_spread: put_spread,
      quantity: 2
    )
  end

  describe '#initialize' do
    it 'sets all attributes' do
      expect(iron_condor.underlying_symbol).to eq('SPY')
      expect(iron_condor.call_spread).to eq(call_spread)
      expect(iron_condor.put_spread).to eq(put_spread)
      expect(iron_condor.quantity).to eq(2)
    end

    it 'uses default values' do
      condor = described_class.new(
        underlying_symbol: 'SPY',
        call_spread: call_spread,
        put_spread: put_spread,
      )

      expect(condor.quantity).to eq(1)
      expect(condor.increment).to eq(0.01)
      expect(condor.round).to eq(2)
    end

    it 'accepts custom increment and round values' do
      condor = described_class.new(
        underlying_symbol: 'SPY',
        call_spread: call_spread,
        put_spread: put_spread,
        increment: 0.05,
        round: 3
      )

      expect(condor.increment).to eq(0.05)
      expect(condor.round).to eq(3)
    end
  end

  describe '#delta' do
    it 'returns the delta with higher absolute value' do
      # call_spread.delta.abs (0.25) > put_spread.delta.abs (0.15)
      expect(iron_condor.delta).to eq(0.25)
    end

    it 'returns put spread delta when it has higher absolute value' do
      allow(put_spread).to receive(:delta).and_return(-0.35)
      # put_spread.delta.abs (0.35) > call_spread.delta.abs (0.25)
      expect(iron_condor.delta).to eq(-0.35)
    end

    it 'handles equal absolute deltas' do
      allow(put_spread).to receive(:delta).and_return(-0.25)
      allow(call_spread).to receive(:delta).and_return(0.25)
      # When equal, it should return call_spread delta
      expect(iron_condor.delta).to eq(0.25)
    end
  end

  describe '#credit' do
    it 'calculates total credit from both spreads' do
      expect(iron_condor.credit).to eq(2.75) # 1.25 + 1.50
    end

    it 'rounds to nearest increment' do
      allow(put_spread).to receive(:credit).and_return(1.23)
      allow(call_spread).to receive(:credit).and_return(1.52)

      expect(iron_condor.credit).to eq(2.75) # 1.23 + 1.52 = 2.75
    end

    it 'handles negative credits' do
      allow(put_spread).to receive(:credit).and_return(-0.50)
      allow(call_spread).to receive(:credit).and_return(2.00)

      expect(iron_condor.credit).to eq(1.50) # -0.50 + 2.00
    end
  end

  describe '#debit' do
    it 'calculates total debit from both spreads' do
      expect(iron_condor.debit).to eq(-2.75) # -1.25 + (-1.50)
    end

    it 'handles positive debits' do
      allow(put_spread).to receive(:debit).and_return(0.50)
      allow(call_spread).to receive(:debit).and_return(1.00)

      expect(iron_condor.debit).to eq(1.50) # 0.50 + 1.00
    end
  end

  describe '#symbols' do
    it 'returns combined symbols from both spreads' do
      expected = ['SPY250620P00450000', 'SPY250620P00440000',
                  'SPY250620C00500000', 'SPY250620C00510000']
      expect(iron_condor.symbols).to eq(expected)
    end
  end

  describe '#strikes' do
    it 'returns combined strikes from both spreads' do
      expected = [450.0, 440.0, 500.0, 510.0]
      expect(iron_condor.strikes).to eq(expected)
    end
  end

  describe '#marks' do
    it 'returns combined marks from both spreads' do
      expected = [2.75, 1.50, 3.50, 2.00]
      expect(iron_condor.marks).to eq(expected)
    end
  end

  describe '#market_change?' do
    it 'returns true if put spread has market change' do
      allow(put_spread).to receive(:market_change?).and_return(true)
      allow(call_spread).to receive(:market_change?).and_return(false)

      expect(iron_condor.market_change?).to be true
    end

    it 'returns true if call spread has market change' do
      allow(put_spread).to receive(:market_change?).and_return(false)
      allow(call_spread).to receive(:market_change?).and_return(true)

      expect(iron_condor.market_change?).to be true
    end

    it 'returns true if both spreads have market change' do
      allow(put_spread).to receive(:market_change?).and_return(true)
      allow(call_spread).to receive(:market_change?).and_return(true)

      expect(iron_condor.market_change?).to be true
    end

    it 'returns false if neither spread has market change' do
      allow(put_spread).to receive(:market_change?).and_return(false)
      allow(call_spread).to receive(:market_change?).and_return(false)

      expect(iron_condor.market_change?).to be false
    end
  end

  describe '#spread_width' do
    it 'returns combined spread width from both spreads' do
      expect(iron_condor.spread_width).to eq(20.0) # 10.0 + 10.0
    end

    it 'handles different spread widths' do
      allow(put_spread).to receive(:spread_width).and_return(5.0)
      allow(call_spread).to receive(:spread_width).and_return(15.0)

      expect(iron_condor.spread_width).to eq(20.0) # 5.0 + 15.0
    end
  end

  describe '#max_profit' do
    it 'returns the total credit as max profit' do
      expect(iron_condor.max_profit).to eq(2.75)
    end
  end

  describe '#max_loss' do
    it 'calculates max loss as spread width minus credit' do
      # spread_width (20.0) - credit (2.75) = 17.25
      expect(iron_condor.max_loss).to eq(17.25)
    end

    it 'rounds to nearest increment' do
      allow(iron_condor).to receive(:spread_width).and_return(20.0)
      allow(iron_condor).to receive(:credit).and_return(2.73)

      expect(iron_condor.max_loss).to eq(17.27) # 20.0 - 2.73
    end
  end

  describe '#check_market' do
    it 'calls check_market on both spreads using threads' do
      expect(call_spread).to receive(:check_market)
      expect(put_spread).to receive(:check_market)

      iron_condor.check_market
    end

    it 'waits for both threads to complete' do
      call_called = false
      put_called = false

      allow(call_spread).to receive(:check_market) do
        sleep(0.01)
        call_called = true
      end

      allow(put_spread).to receive(:check_market) do
        sleep(0.01)
        put_called = true
      end

      iron_condor.check_market

      expect(call_called).to be true
      expect(put_called).to be true
    end
  end

  describe '#to_s' do
    it 'returns formatted string representation' do
      expected = "<OptionsTrader::IronCondor | #{Date.new(2025, 6, 20)} | 2.75 | " \
                 "PUTSPREAD 450.0/440.0 | " \
                 "CALLSPREAD 500.0/510.0>"

      expect(iron_condor.to_s).to eq(expected)
    end

    it 'handles different strike configurations' do
      allow(put_spread).to receive(:strikes).and_return([455.0, 445.0])
      allow(call_spread).to receive(:strikes).and_return([505.0, 515.0])
      allow(iron_condor).to receive(:credit).and_return(3.25)

      expected = "<OptionsTrader::IronCondor | #{Date.new(2025, 6, 20)} | 3.25 | " \
                 "PUTSPREAD 455.0/445.0 | " \
                 "CALLSPREAD 505.0/515.0>"

      expect(iron_condor.to_s).to eq(expected)
    end
  end

  describe 'inheritance' do
    it 'inherits from StrategyBase' do
      expect(iron_condor).to be_a(OptionsTrader::StrategyBase)
    end

    it 'responds to StrategyBase methods' do
      expect(iron_condor).to respond_to(:type)
      expect(iron_condor).to respond_to(:nearest_increment)
      expect(iron_condor).to respond_to(:increment)
      expect(iron_condor).to respond_to(:round)
    end
  end

  describe 'risk analysis' do
    it 'has proper risk/reward characteristics' do
      # Max profit should be the credit received
      expect(iron_condor.max_profit).to eq(iron_condor.credit)

      # Max loss should be spread width minus credit
      expected_max_loss = iron_condor.spread_width - iron_condor.credit
      expect(iron_condor.max_loss).to eq(expected_max_loss)

      # Profit/loss ratio should be reasonable for iron condors
      profit_loss_ratio = iron_condor.max_profit / iron_condor.max_loss
      expect(profit_loss_ratio).to be > 0.05  # At least 5% return potential
      expect(profit_loss_ratio).to be < 1.0   # Max loss should exceed max profit
    end
  end

  describe 'serialization' do
    let(:put_spread_with_to_h) do
      double('PutSpread',
        delta: -0.15,
        credit: 1.25,
        debit: -1.25,
        symbols: ['SPY250620P00450000', 'SPY250620P00440000'],
        strikes: [450.0, 440.0],
        marks: [2.75, 1.50],
        spread_width: 10.0,
        market_change?: false,
        check_market: nil,
        expiration_date: Date.new(2025, 6, 20),
        instruments: [
          { symbol: 'SPY250620P00450000', long_short: 'SHORT', put_call: 'PUT' },
          { symbol: 'SPY250620P00440000', long_short: 'LONG', put_call: 'PUT' }
        ],
        to_h: {
          type: 'putspread',
          quantity: 1,
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
      )
    end

    let(:call_spread_with_to_h) do
      double('CallSpread',
        delta: 0.25,
        credit: 1.50,
        debit: -1.50,
        symbols: ['SPY250620C00500000', 'SPY250620C00510000'],
        strikes: [500.0, 510.0],
        marks: [3.50, 2.00],
        spread_width: 10.0,
        market_change?: false,
        check_market: nil,
        expiration_date: Date.new(2025, 6, 20),
        instruments: [
          { symbol: 'SPY250620C00500000', long_short: 'SHORT', put_call: 'CALL' },
          { symbol: 'SPY250620C00510000', long_short: 'LONG', put_call: 'CALL' }
        ],
        to_h: {
          type: 'callspread',
          quantity: 1,
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
      )
    end

    let(:iron_condor_for_serialization) do
      described_class.new(
        underlying_symbol: 'SPY',
        call_spread: call_spread_with_to_h,
        put_spread: put_spread_with_to_h,
        quantity: 2
      )
    end

    let(:iron_condor_hash) do
      {
        type: 'ironcondor',
        quantity: 3,
        underlying_symbol: 'SPY',
        round: 2,
        increment: 0.01,
        put_spread: {
          type: 'putspread',
          quantity: 1,
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
        },
        call_spread: {
          type: 'callspread',
          quantity: 1,
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
      }
    end

    describe '#to_h' do
      it 'returns hash representation with all attributes' do
        result = iron_condor_for_serialization.to_h

        expect(result).to be_a(Hash)
        expect(result[:type]).to eq('ironcondor')
        expect(result[:quantity]).to eq(2)
        expect(result[:underlying_symbol]).to eq('SPY')
        expect(result[:round]).to eq(2)
        expect(result[:increment]).to eq(0.01)
      end

      it 'includes nested spread data' do
        result = iron_condor_for_serialization.to_h

        expect(result[:put_spread]).to be_a(Hash)
        expect(result[:call_spread]).to be_a(Hash)
        expect(result[:put_spread][:type]).to eq('putspread')
        expect(result[:call_spread][:type]).to eq('callspread')
      end
    end

    describe '#to_json' do
      it 'converts to JSON string' do
        json_string = iron_condor_for_serialization.to_json
        expect(json_string).to be_a(String)

        parsed = JSON.parse(json_string, symbolize_names: true)
        expect(parsed[:type]).to eq('ironcondor')
        expect(parsed[:underlying_symbol]).to eq('SPY')
      end
    end

    describe '.from_h' do
      it 'reconstructs IronCondor from hash' do
        condor = described_class.from_h(iron_condor_hash)

        expect(condor).to be_a(OptionsTrader::IronCondor)
        expect(condor.underlying_symbol).to eq('SPY')
        expect(condor.quantity).to eq(3)
        expect(condor.increment).to eq(0.01)
        expect(condor.round).to eq(2)
        expect(condor.expiration_date).to eq(Date.new(2025, 6, 20))
      end

      it 'reconstructs nested spread objects' do
        condor = described_class.from_h(iron_condor_hash)

        expect(condor.put_spread).to be_a(OptionsTrader::PutSpread)
        expect(condor.call_spread).to be_a(OptionsTrader::CallSpread)

        expect(condor.put_spread.underlying_symbol).to eq('SPY')
        expect(condor.call_spread.underlying_symbol).to eq('SPY')
      end
    end

    describe '.from_json' do
      it 'reconstructs IronCondor from JSON string' do
        json_string = iron_condor_hash.to_json
        condor = described_class.from_json(json_string)

        expect(condor).to be_a(OptionsTrader::IronCondor)
        expect(condor.underlying_symbol).to eq('SPY')
        expect(condor.quantity).to eq(3)
      end

      it 'round-trip serialization preserves data' do
        original_condor = described_class.new(
          underlying_symbol: 'TEST',
          call_spread: call_spread_with_to_h,
          put_spread: put_spread_with_to_h,
          quantity: 5,
          increment: 0.05,
          round: 3
        )

        json_string = original_condor.to_json
        reconstructed = described_class.from_json(json_string)

        expect(reconstructed.underlying_symbol).to eq(original_condor.underlying_symbol)
        expect(reconstructed.quantity).to eq(original_condor.quantity)
        expect(reconstructed.increment).to eq(original_condor.increment)
        expect(reconstructed.round).to eq(original_condor.round)
        expect(reconstructed.expiration_date).to eq(original_condor.expiration_date)
      end
    end
  end

  describe '#extract_kwargs' do
    it 'returns correct kwargs for :open instruction' do
      allow(iron_condor).to receive(:strategy_price).with(:open).and_return(2.75)
      
      kwargs = iron_condor.extract_kwargs(:open)
      
      expect(kwargs).to eq({
        strategy_type: 'ironcondor',
        put_short_symbol: 'SPY250620P00450000',
        put_long_symbol: 'SPY250620P00440000',
        call_short_symbol: 'SPY250620C00500000',
        call_long_symbol: 'SPY250620C00510000',
        price: 2.75,
        quantity: 2
      })
    end

    it 'returns correct kwargs for :exit instruction' do
      allow(iron_condor).to receive(:strategy_price).with(:exit).and_return(1.35)
      
      kwargs = iron_condor.extract_kwargs(:exit)
      
      expect(kwargs).to eq({
        strategy_type: 'ironcondor',
        put_short_symbol: 'SPY250620P00450000',
        put_long_symbol: 'SPY250620P00440000',
        call_short_symbol: 'SPY250620C00500000',
        call_long_symbol: 'SPY250620C00510000',
        price: 1.35,
        quantity: 2
      })
    end
  end
end
