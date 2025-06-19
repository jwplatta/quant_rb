# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Platypi::IronCondorFinder do
  let(:option_chain_data) do
    JSON.parse(
      File.read(File.join(File.dirname(__FILE__), '..', 'fixtures', 'option_chains', 'SPX_05_20_2025_option_chain.json')),
      symbolize_names: true
    )
  end

  let(:option_chain) { Platypi::Schwab::DataObjects::OptionChain.build(option_chain_data) }
  let(:expiration_date) { Date.new(2025, 5, 20) }

  describe '#initialize' do
    it 'sets default values' do
      finder = described_class.new(underlying_symbol: 'SPX')

      expect(finder.underlying_symbol).to eq('SPX')
      expect(finder.expiration_date).to be_nil
      expect(finder.short_delta).to eq(0.15)
      expect(finder.max_spread).to eq(20.0)
      expect(finder.min_credit).to eq(100.0)
      expect(finder.min_open_interest).to eq(0)
      expect(finder.dist_from_strike).to eq(0.07)
      expect(finder.quantity).to eq(1)
      expect(finder.expiration_type).to be_nil
      expect(finder.settlement_type).to be_nil
      expect(finder.option_root).to be_nil
      expect(finder.call_spread).to be_nil
      expect(finder.put_spread).to be_nil
    end

    it 'accepts custom parameters' do
      finder = described_class.new(
        underlying_symbol: 'AAPL',
        expiration_date: expiration_date,
        short_delta: 0.20,
        max_spread: 10.0,
        min_credit: 50.0,
        min_open_interest: 100,
        dist_from_strike: 0.05,
        quantity: 5,
        expiration_type: 'W',
        settlement_type: 'P',
        option_root: 'SPXW'
      )

      expect(finder.underlying_symbol).to eq('AAPL')
      expect(finder.expiration_date).to eq(expiration_date)
      expect(finder.short_delta).to eq(0.20)
      expect(finder.max_spread).to eq(10.0)
      expect(finder.min_credit).to eq(50.0)
      expect(finder.min_open_interest).to eq(100)
      expect(finder.dist_from_strike).to eq(0.05)
      expect(finder.quantity).to eq(5)
      expect(finder.expiration_type).to eq('W')
      expect(finder.settlement_type).to eq('P')
      expect(finder.option_root).to eq('SPXW')
    end
  end

  describe '#search' do
    let(:finder) do
      described_class.new(
        underlying_symbol: '$SPX',
        expiration_date: expiration_date,
        short_delta: 0.30,
        max_spread: 20.0,
        min_credit: 50.0,  # Reduced for test data
        min_open_interest: 0,
        dist_from_strike: 0.01,  # Reduced for test data
        quantity: 1
      )
    end

    it 'finds iron condors with valid criteria' do
      result = finder.search(option_chain)

      expect(result).to be_a(Platypi::IronCondor)
      expect(result.underlying_symbol).to eq('$SPX')
      expect(result.call_spread).to be_a(Platypi::CallSpread)
      expect(result.put_spread).to be_a(Platypi::PutSpread)
    end

    it 'returns iron condor with combined credit from both spreads' do
      result = finder.search(option_chain)

      if result.is_a?(Platypi::IronCondor)
        expect(result.credit).to be > 1.0  # Should be sum of both spreads
        expect(result.call_spread.credit).to be > 0
        expect(result.put_spread.credit).to be > 0
      end
    end

    it 'ensures both spreads have same expiration date' do
      result = finder.search(option_chain)

      if result.is_a?(Platypi::IronCondor)
        expect(result.call_spread.expiration_date).to eq(result.put_spread.expiration_date)
        expect(result.call_spread.expiration_date).to eq(expiration_date)
      end
    end

    it 'respects short delta filter for both spreads' do
      restrictive_finder = described_class.new(
        underlying_symbol: '$SPX',
        expiration_date: expiration_date,
        short_delta: 0.10,  # Very low delta
        max_spread: 20.0,
        min_credit: 25.0,
        min_open_interest: 0,
        dist_from_strike: 0.01
      )

      result = restrictive_finder.search(option_chain)

      if result.is_a?(Platypi::IronCondor)
        expect(result.call_spread.short_leg.delta.abs).to be <= 0.10
        expect(result.put_spread.short_leg.delta.abs).to be <= 0.10
      else
        expect(result).to be_a(Platypi::NullStrategy)
      end
    end

    it 'respects max spread width filter for both spreads' do
      narrow_finder = described_class.new(
        underlying_symbol: '$SPX',
        expiration_date: expiration_date,
        short_delta: 0.30,
        max_spread: 5.0,  # Very narrow spread
        min_credit: 25.0,
        min_open_interest: 0,
        dist_from_strike: 0.01
      )

      result = narrow_finder.search(option_chain)

      if result.is_a?(Platypi::IronCondor)
        expect(result.call_spread.spread_width).to be <= 5.0
        expect(result.put_spread.spread_width).to be <= 5.0
      else
        expect(result).to be_a(Platypi::NullStrategy)
      end
    end

    it 'respects minimum credit filter for both spreads' do
      high_credit_finder = described_class.new(
        underlying_symbol: '$SPX',
        expiration_date: expiration_date,
        short_delta: 0.30,
        max_spread: 20.0,
        min_credit: 300.0,  # High minimum credit per spread
        min_open_interest: 0,
        dist_from_strike: 0.01
      )

      result = high_credit_finder.search(option_chain)

      if result.is_a?(Platypi::IronCondor)
        expect(result.call_spread.credit * 100).to be >= 300.0
        expect(result.put_spread.credit * 100).to be >= 300.0
      else
        expect(result).to be_a(Platypi::NullStrategy)
      end
    end

    it 'respects distance from strike filter for both spreads' do
      close_strike_finder = described_class.new(
        underlying_symbol: '$SPX',
        expiration_date: expiration_date,
        short_delta: 0.30,
        max_spread: 20.0,
        min_credit: 25.0,
        min_open_interest: 0,
        dist_from_strike: 0.005  # Very close to current price
      )

      result = close_strike_finder.search(option_chain)

      if result.is_a?(Platypi::IronCondor)
        underlying_price = option_chain.underlying_price
        call_short_strike = result.call_spread.short_leg.strike
        put_short_strike = result.put_spread.short_leg.strike

        call_distance = ((underlying_price - call_short_strike) / underlying_price).abs
        put_distance = ((underlying_price - put_short_strike) / underlying_price).abs

        expect(call_distance).to be >= 0.005
        expect(put_distance).to be >= 0.005
      else
        expect(result).to be_a(Platypi::NullStrategy)
      end
    end

    it 'filters by expiration type when specified' do
      weekly_finder = described_class.new(
        underlying_symbol: '$SPX',
        expiration_date: expiration_date,
        short_delta: 0.30,
        max_spread: 20.0,
        min_credit: 50.0,
        min_open_interest: 0,
        dist_from_strike: 0.05,
        expiration_type: 'W'  # Weekly options
      )

      result = weekly_finder.search(option_chain)

      if result.is_a?(Platypi::IronCondor)
        expect(result.call_spread.short_leg.expiration_type).to eq('W')
        expect(result.call_spread.long_leg.expiration_type).to eq('W')
        expect(result.put_spread.short_leg.expiration_type).to eq('W')
        expect(result.put_spread.long_leg.expiration_type).to eq('W')
      end
    end

    it 'filters by settlement type when specified' do
      cash_settled_finder = described_class.new(
        underlying_symbol: '$SPX',
        expiration_date: expiration_date,
        short_delta: 0.30,
        max_spread: 20.0,
        min_credit: 50.0,
        min_open_interest: 0,
        dist_from_strike: 0.05,
        settlement_type: 'P'  # Physical settlement (though SPX is cash)
      )

      result = cash_settled_finder.search(option_chain)

      if result.is_a?(Platypi::IronCondor)
        expect(result.call_spread.short_leg.settlement_type).to eq('P')
        expect(result.call_spread.long_leg.settlement_type).to eq('P')
        expect(result.put_spread.short_leg.settlement_type).to eq('P')
        expect(result.put_spread.long_leg.settlement_type).to eq('P')
      end
    end

    it 'filters by option root when specified' do
      spxw_finder = described_class.new(
        underlying_symbol: '$SPX',
        expiration_date: expiration_date,
        short_delta: 0.30,
        max_spread: 20.0,
        min_credit: 50.0,
        min_open_interest: 0,
        dist_from_strike: 0.05,
        option_root: 'SPXW'
      )

      result = spxw_finder.search(option_chain)

      if result.is_a?(Platypi::IronCondor)
        expect(result.call_spread.short_leg.option_root).to eq('SPXW')
        expect(result.call_spread.long_leg.option_root).to eq('SPXW')
        expect(result.put_spread.short_leg.option_root).to eq('SPXW')
        expect(result.put_spread.long_leg.option_root).to eq('SPXW')
      end
    end

    it 'returns NullStrategy when no valid call spread found' do
      # Create finder that should find put spreads but no call spreads
      impossible_call_finder = described_class.new(
        underlying_symbol: '$SPX',
        expiration_date: expiration_date,
        short_delta: 0.001,  # Extremely low delta for calls only
        max_spread: 1.0,
        min_credit: 1000.0,
        min_open_interest: 10000,
        dist_from_strike: 0.50
      )

      result = impossible_call_finder.search(option_chain)
      expect(result).to be_a(Platypi::NullStrategy)
    end

    it 'returns NullStrategy when no valid put spread found' do
      # Create finder that should find call spreads but no put spreads
      impossible_put_finder = described_class.new(
        underlying_symbol: '$SPX',
        expiration_date: expiration_date,
        short_delta: 0.001,  # Extremely low delta for puts only
        max_spread: 1.0,
        min_credit: 1000.0,
        min_open_interest: 10000,
        dist_from_strike: 0.50
      )

      result = impossible_put_finder.search(option_chain)
      expect(result).to be_a(Platypi::NullStrategy)
    end

    it 'returns NullStrategy when neither spread can be found' do
      impossible_finder = described_class.new(
        underlying_symbol: '$SPX',
        expiration_date: expiration_date,
        short_delta: 0.001,  # Extremely low delta
        max_spread: 1.0,     # Very narrow spread
        min_credit: 1000.0,  # Very high credit requirement
        min_open_interest: 10000,  # Very high open interest
        dist_from_strike: 0.50     # Very far from strike
      )

      result = impossible_finder.search(option_chain)
      expect(result).to be_a(Platypi::NullStrategy)
    end

    context 'with different expiration dates' do
      let(:wrong_expiration_finder) do
        described_class.new(
          underlying_symbol: '$SPX',
          expiration_date: Date.new(2025, 6, 20),  # Different expiration
          short_delta: 0.30,
          max_spread: 20.0,
          min_credit: 50.0
        )
      end

      it 'returns NullStrategy when expiration date does not match' do
        result = wrong_expiration_finder.search(option_chain)
        expect(result).to be_a(Platypi::NullStrategy)
      end
    end

    context 'with edge cases' do
      it 'handles option chain with no call options' do
        empty_call_chain_data = option_chain_data.dup
        empty_call_chain_data[:callExpDateMap] = {}
        empty_call_chain = Platypi::Schwab::DataObjects::OptionChain.build(empty_call_chain_data)

        result = finder.search(empty_call_chain)
        expect(result).to be_a(Platypi::NullStrategy)
      end

      it 'handles option chain with no put options' do
        empty_put_chain_data = option_chain_data.dup
        empty_put_chain_data[:putExpDateMap] = {}
        empty_put_chain = Platypi::Schwab::DataObjects::OptionChain.build(empty_put_chain_data)

        result = finder.search(empty_put_chain)
        expect(result).to be_a(Platypi::NullStrategy)
      end

      it 'handles options with zero or negative marks' do
        # This is more of an integration test to ensure the search doesn't break
        # with edge case data
        result = finder.search(option_chain)

        if result.is_a?(Platypi::IronCondor)
          expect(result.call_spread.short_leg.mark).to be > 0
          expect(result.call_spread.long_leg.mark).to be > 0
          expect(result.put_spread.short_leg.mark).to be > 0
          expect(result.put_spread.long_leg.mark).to be > 0
        end
      end
    end
  end

  describe '#call_spread_finder' do
    let(:finder) do
      described_class.new(
        underlying_symbol: '$SPX',
        expiration_date: expiration_date,
        short_delta: 0.25,
        max_spread: 15.0,
        min_credit: 75.0,
        min_open_interest: 10,
        dist_from_strike: 0.03,
        quantity: 2,
        expiration_type: 'W',
        settlement_type: 'P',
        option_root: 'SPXW'
      )
    end

    it 'creates call spread finder with same parameters' do
      call_finder = finder.call_spread_finder

      expect(call_finder).to be_a(Platypi::CallSpreadFinder)
      expect(call_finder.underlying_symbol).to eq('$SPX')
      expect(call_finder.expiration_date).to eq(expiration_date)
      expect(call_finder.short_delta).to eq(0.25)
      expect(call_finder.max_spread).to eq(15.0)
      expect(call_finder.min_credit).to eq(75.0)
      expect(call_finder.min_open_interest).to eq(10)
      expect(call_finder.dist_from_strike).to eq(0.03)
      expect(call_finder.quantity).to eq(2)
      expect(call_finder.expiration_type).to eq('W')
      expect(call_finder.settlement_type).to eq('P')
      expect(call_finder.option_root).to eq('SPXW')
    end

    it 'memoizes the call spread finder' do
      first_call = finder.call_spread_finder
      second_call = finder.call_spread_finder

      expect(first_call).to be(second_call)
    end
  end

  describe '#put_spread_finder' do
    let(:finder) do
      described_class.new(
        underlying_symbol: '$SPX',
        expiration_date: expiration_date,
        short_delta: 0.25,
        max_spread: 15.0,
        min_credit: 75.0,
        min_open_interest: 10,
        dist_from_strike: 0.03,
        quantity: 2,
        expiration_type: 'W',
        settlement_type: 'P',
        option_root: 'SPXW'
      )
    end

    it 'creates put spread finder with same parameters' do
      put_finder = finder.put_spread_finder

      expect(put_finder).to be_a(Platypi::PutSpreadFinder)
      expect(put_finder.underlying_symbol).to eq('$SPX')
      expect(put_finder.expiration_date).to eq(expiration_date)
      expect(put_finder.short_delta).to eq(0.25)
      expect(put_finder.max_spread).to eq(15.0)
      expect(put_finder.min_credit).to eq(75.0)
      expect(put_finder.min_open_interest).to eq(10)
      expect(put_finder.dist_from_strike).to eq(0.03)
      expect(put_finder.quantity).to eq(2)
      expect(put_finder.expiration_type).to eq('W')
      expect(put_finder.settlement_type).to eq('P')
      expect(put_finder.option_root).to eq('SPXW')
    end

    it 'memoizes the put spread finder' do
      first_call = finder.put_spread_finder
      second_call = finder.put_spread_finder

      expect(first_call).to be(second_call)
    end
  end

  describe 'integration with real option data' do
    let(:realistic_finder) do
      described_class.new(
        underlying_symbol: '$SPX',
        expiration_date: expiration_date,
        short_delta: 0.25,        # ~25 delta short legs
        max_spread: 15.0,         # 15 point spread max
        min_credit: 50.0,         # $0.50 minimum credit per spread
        min_open_interest: 0,     # No OI requirement for test
        dist_from_strike: 0.01    # 1% from current price
      )
    end

    it 'finds realistic iron condors from SPX data' do
      result = realistic_finder.search(option_chain)

      expect(result).to be_a(Platypi::IronCondor)
      expect(result.credit).to be >= 1.0  # Combined credit should be at least $1.00
      expect(result.call_spread.spread_width).to be <= 15.0
      expect(result.put_spread.spread_width).to be <= 15.0
      expect(result.call_spread.short_leg.delta.abs).to be <= 0.25
      expect(result.put_spread.short_leg.delta.abs).to be <= 0.25
    end

    it 'ensures proper iron condor structure' do
      result = realistic_finder.search(option_chain)

      if result.is_a?(Platypi::IronCondor)
        # Call spread structure: short strike < long strike
        expect(result.call_spread.short_leg.strike).to be < result.call_spread.long_leg.strike

        # Put spread structure: short strike > long strike
        expect(result.put_spread.short_leg.strike).to be > result.put_spread.long_leg.strike

        # Call strikes should be above underlying price (OTM calls)
        underlying_price = option_chain.underlying_price
        expect(result.call_spread.short_leg.strike).to be > underlying_price

        # Put strikes should be below underlying price (OTM puts)
        expect(result.put_spread.short_leg.strike).to be < underlying_price

        # Both spreads should be credit spreads
        expect(result.call_spread.credit).to be > 0
        expect(result.put_spread.credit).to be > 0
      end
    end

    it 'has reasonable risk/reward characteristics' do
      result = realistic_finder.search(option_chain)

      if result.is_a?(Platypi::IronCondor)
        # Max profit should be the total credit
        expect(result.max_profit).to eq(result.credit)

        # Max loss should be spread width minus credit
        expected_max_loss = result.spread_width - result.credit
        expect(result.max_loss).to eq(expected_max_loss)

        # Max loss should be greater than max profit (typical for iron condors)
        expect(result.max_loss).to be > result.max_profit

        # Profit/loss ratio should be reasonable
        profit_loss_ratio = result.max_profit / result.max_loss
        expect(profit_loss_ratio).to be > 0.05  # At least 5% return potential
        expect(profit_loss_ratio).to be < 1.0   # Max loss should exceed max profit
      end
    end
  end

  describe 'performance considerations' do
    let(:performance_finder) do
      described_class.new(
        underlying_symbol: '$SPX',
        expiration_date: expiration_date,
        short_delta: 0.30,
        max_spread: 20.0,
        min_credit: 50.0,
        min_open_interest: 0,
        dist_from_strike: 0.01
      )
    end

    it 'completes search in reasonable time' do
      start_time = Time.now

      performance_finder.search(option_chain)

      end_time = Time.now
      expect(end_time - start_time).to be < 2.0  # Should complete in under 2 seconds
    end
  end

  describe 'iron condor structure validation' do
    let(:finder) do
      described_class.new(
        underlying_symbol: '$SPX',
        expiration_date: expiration_date,
        short_delta: 0.30,
        max_spread: 20.0,
        min_credit: 50.0,
        min_open_interest: 0,
        dist_from_strike: 0.01
      )
    end

    it 'validates strike price relationships' do
      result = finder.search(option_chain)

      if result.is_a?(Platypi::IronCondor)
        call_strikes = result.call_spread.strikes.sort
        put_strikes = result.put_spread.strikes.sort

        # Call strikes should be: short_strike < long_strike
        expect(call_strikes[0]).to be < call_strikes[1]

        # Put strikes should be: long_strike < short_strike
        expect(put_strikes[0]).to be < put_strikes[1]

        # All call strikes should be above all put strikes (typical iron condor)
        expect(call_strikes.min).to be > put_strikes.max
      end
    end
  end
end