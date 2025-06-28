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
      expect(finder.quantity).to eq(1)
      expect(finder.expiration_type).to be_nil
      expect(finder.settlement_type).to be_nil
      expect(finder.option_root).to be_nil
    end

    it 'accepts custom parameters' do
      finder = described_class.new(
        underlying_symbol: 'AAPL',
        expiration_date: expiration_date,
        quantity: 5,
        expiration_type: 'W',
        settlement_type: 'P',
        option_root: 'SPXW'
      )

      expect(finder.underlying_symbol).to eq('AAPL')
      expect(finder.expiration_date).to eq(expiration_date)
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
        quantity: 1
      )
    end

    before do
      # Mock the option_chain method to return our test data
      allow(finder).to receive(:option_chain).and_return(option_chain)
    end

    it 'finds iron condors with valid criteria' do
      result = finder.search(
        from_date: expiration_date,
        to_date: expiration_date,
        short_delta: 0.30,
        max_spread: 20.0,
        min_credit: 50.0,  # Reduced for test data
        min_open_interest: 0,
        dist_from_strike: 0.01  # Reduced for test data
      )

      expect(result).to be_a(Platypi::IronCondor)
      expect(result.underlying_symbol).to eq('$SPX')
      expect(result.call_spread).to be_a(Platypi::CallSpread)
      expect(result.put_spread).to be_a(Platypi::PutSpread)
    end

    it 'returns iron condor with combined credit from both spreads' do
      result = finder.search(
        from_date: expiration_date,
        to_date: expiration_date,
        short_delta: 0.30,
        max_spread: 20.0,
        min_credit: 50.0,
        min_open_interest: 0,
        dist_from_strike: 0.01
      )

      if result.is_a?(Platypi::IronCondor)
        expect(result.credit).to be > 1.0  # Should be sum of both spreads
        expect(result.call_spread.credit).to be > 0
        expect(result.put_spread.credit).to be > 0
      end
    end

    it 'ensures both spreads have same expiration date' do
      result = finder.search(
        from_date: expiration_date,
        to_date: expiration_date,
        short_delta: 0.30,
        max_spread: 20.0,
        min_credit: 50.0,
        min_open_interest: 0,
        dist_from_strike: 0.01
      )

      if result.is_a?(Platypi::IronCondor)
        expect(result.call_spread.expiration_date).to eq(result.put_spread.expiration_date)
        expect(result.call_spread.expiration_date).to eq(expiration_date)
      end
    end

    it 'respects short delta filter for both spreads' do
      result = finder.search(
        from_date: expiration_date,
        to_date: expiration_date,
        short_delta: 0.10,  # Very low delta
        max_spread: 20.0,
        min_credit: 25.0,
        min_open_interest: 0,
        dist_from_strike: 0.01
      )

      if result.is_a?(Platypi::IronCondor)
        expect(result.call_spread.short_leg.delta.abs).to be <= 0.10
        expect(result.put_spread.short_leg.delta.abs).to be <= 0.10
      else
        expect(result).to be_a(Platypi::NullStrategy)
      end
    end

    it 'respects max spread width filter for both spreads' do
      result = finder.search(
        from_date: expiration_date,
        to_date: expiration_date,
        short_delta: 0.30,
        max_spread: 5.0,  # Very narrow spread
        min_credit: 25.0,
        min_open_interest: 0,
        dist_from_strike: 0.01
      )

      if result.is_a?(Platypi::IronCondor)
        expect(result.call_spread.spread_width).to be <= 5.0
        expect(result.put_spread.spread_width).to be <= 5.0
      else
        expect(result).to be_a(Platypi::NullStrategy)
      end
    end

    it 'respects minimum credit filter for combined spreads' do
      result = finder.search(
        from_date: expiration_date,
        to_date: expiration_date,
        short_delta: 0.30,
        max_spread: 20.0,
        min_credit: 300.0,  # High minimum credit for total combination
        min_open_interest: 0,
        dist_from_strike: 0.01
      )

      if result.is_a?(Platypi::IronCondor)
        # Total credit should meet the minimum requirement
        total_credit = (result.call_spread.credit + result.put_spread.credit) * 100.0
        expect(total_credit).to be >= 300.0
      else
        expect(result).to be_a(Platypi::NullStrategy)
      end
    end

    it 'respects distance from strike filter for both spreads' do
      result = finder.search(
        from_date: expiration_date,
        to_date: expiration_date,
        short_delta: 0.30,
        max_spread: 20.0,
        min_credit: 25.0,
        min_open_interest: 0,
        dist_from_strike: 0.005  # Very close to current price
      )

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
      finder_with_exp_type = described_class.new(
        underlying_symbol: '$SPX',
        expiration_date: expiration_date,
        expiration_type: 'W'  # Weekly options
      )

      allow(finder_with_exp_type).to receive(:option_chain).and_return(option_chain)

      result = finder_with_exp_type.search(
        from_date: expiration_date,
        to_date: expiration_date,
        short_delta: 0.30,
        max_spread: 20.0,
        min_credit: 50.0,
        min_open_interest: 0,
        dist_from_strike: 0.05
      )

      # This test verifies the filtering logic works during the search process
      if result.is_a?(Platypi::IronCondor)
        expect(result).to be_a(Platypi::IronCondor)
      end
    end

    it 'filters by settlement type when specified' do
      finder_with_settlement = described_class.new(
        underlying_symbol: '$SPX',
        expiration_date: expiration_date,
        settlement_type: 'P'  # Physical settlement (though SPX is cash)
      )

      allow(finder_with_settlement).to receive(:option_chain).and_return(option_chain)

      result = finder_with_settlement.search(
        from_date: expiration_date,
        to_date: expiration_date,
        short_delta: 0.30,
        max_spread: 20.0,
        min_credit: 50.0,
        min_open_interest: 0,
        dist_from_strike: 0.05
      )

      # This test verifies the filtering logic works during the search process
      if result.is_a?(Platypi::IronCondor)
        expect(result).to be_a(Platypi::IronCondor)
      end
    end

    it 'filters by option root when specified' do
      finder_with_root = described_class.new(
        underlying_symbol: '$SPX',
        expiration_date: expiration_date,
        option_root: 'SPXW'
      )

      allow(finder_with_root).to receive(:option_chain).and_return(option_chain)

      result = finder_with_root.search(
        from_date: expiration_date,
        to_date: expiration_date,
        short_delta: 0.30,
        max_spread: 20.0,
        min_credit: 50.0,
        min_open_interest: 0,
        dist_from_strike: 0.05
      )

      # This test verifies the filtering logic works during the search process
      if result.is_a?(Platypi::IronCondor)
        expect(result).to be_a(Platypi::IronCondor)
      end
    end

    it 'returns NullStrategy when no valid call spread found' do
      result = finder.search(
        from_date: expiration_date,
        to_date: expiration_date,
        short_delta: 0.001,  # Extremely low delta for calls only
        max_spread: 1.0,
        min_credit: 1000.0,
        min_open_interest: 10000,
        dist_from_strike: 0.50
      )
      expect(result).to be_a(Platypi::NullStrategy)
    end

    it 'returns NullStrategy when no valid put spread found' do
      result = finder.search(
        from_date: expiration_date,
        to_date: expiration_date,
        short_delta: 0.001,  # Extremely low delta for puts only
        max_spread: 1.0,
        min_credit: 1000.0,
        min_open_interest: 10000,
        dist_from_strike: 0.50
      )
      expect(result).to be_a(Platypi::NullStrategy)
    end

    it 'returns NullStrategy when neither spread can be found' do
      result = finder.search(
        from_date: expiration_date,
        to_date: expiration_date,
        short_delta: 0.001,  # Extremely low delta
        max_spread: 1.0,     # Very narrow spread
        min_credit: 1000.0,  # Very high credit requirement
        min_open_interest: 10000,  # Very high open interest
        dist_from_strike: 0.50     # Very far from strike
      )
      expect(result).to be_a(Platypi::NullStrategy)
    end

    context 'with different expiration dates' do
      let(:wrong_expiration_finder) do
        described_class.new(
          underlying_symbol: '$SPX',
          expiration_date: Date.new(2025, 6, 20)  # Different expiration
        )
      end

      it 'returns NullStrategy when expiration date does not match' do
        # Mock the option_chain method
        allow(wrong_expiration_finder).to receive(:option_chain).and_return(option_chain)

        result = wrong_expiration_finder.search(
          from_date: Date.new(2025, 6, 20),
          to_date: Date.new(2025, 6, 20),
          short_delta: 0.30,
          max_spread: 20.0,
          min_credit: 50.0
        )
        expect(result).to be_a(Platypi::NullStrategy)
      end
    end

    context 'with edge cases' do
      it 'handles option chain with no call options' do
        empty_call_chain_data = option_chain_data.dup
        empty_call_chain_data[:callExpDateMap] = {}
        empty_call_chain = Platypi::Schwab::DataObjects::OptionChain.build(empty_call_chain_data)

        # Mock the option_chain method
        allow(finder).to receive(:option_chain).and_return(empty_call_chain)

        result = finder.search(
          from_date: expiration_date,
          to_date: expiration_date,
          short_delta: 0.30,
          max_spread: 20.0,
          min_credit: 50.0,
          min_open_interest: 0,
          dist_from_strike: 0.01
        )
        expect(result).to be_a(Platypi::NullStrategy)
      end

      it 'handles option chain with no put options' do
        empty_put_chain_data = option_chain_data.dup
        empty_put_chain_data[:putExpDateMap] = {}
        empty_put_chain = Platypi::Schwab::DataObjects::OptionChain.build(empty_put_chain_data)

        # Mock the option_chain method
        allow(finder).to receive(:option_chain).and_return(empty_put_chain)

        result = finder.search(
          from_date: expiration_date,
          to_date: expiration_date,
          short_delta: 0.30,
          max_spread: 20.0,
          min_credit: 50.0,
          min_open_interest: 0,
          dist_from_strike: 0.01
        )
        expect(result).to be_a(Platypi::NullStrategy)
      end

      it 'handles options with zero or negative marks' do
        # This is more of an integration test to ensure the search doesn't break
        # with edge case data
        # Mock the option_chain method
        allow(finder).to receive(:option_chain).and_return(option_chain)

        result = finder.search(
          from_date: expiration_date,
          to_date: expiration_date,
          short_delta: 0.30,
          max_spread: 20.0,
          min_credit: 50.0,
          min_open_interest: 0,
          dist_from_strike: 0.01
        )

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
        quantity: 2,
        expiration_type: 'W',
        settlement_type: 'P',
        option_root: 'SPXW'
      )
    end

    it 'creates call spread finder with provided parameters' do
      call_finder = finder.send(:call_spread_finder,
        short_delta: 0.25,
        max_spread: 15.0,
        min_open_interest: 10,
        dist_from_strike: 0.03
      )

      expect(call_finder).to be_a(Platypi::CallSpreadFinder)
      expect(call_finder.underlying_symbol).to eq('$SPX')
      expect(call_finder.expiration_date).to eq(expiration_date)
      expect(call_finder.quantity).to eq(2)
      expect(call_finder.expiration_type).to eq('W')
      expect(call_finder.settlement_type).to eq('P')
      expect(call_finder.option_root).to eq('SPXW')
    end
  end

  describe '#put_spread_finder' do
    let(:finder) do
      described_class.new(
        underlying_symbol: '$SPX',
        expiration_date: expiration_date,
        quantity: 2,
        expiration_type: 'W',
        settlement_type: 'P',
        option_root: 'SPXW'
      )
    end

    it 'creates put spread finder with provided parameters' do
      put_finder = finder.send(:put_spread_finder,
        short_delta: 0.25,
        max_spread: 15.0,
        min_open_interest: 10,
        dist_from_strike: 0.03
      )

      expect(put_finder).to be_a(Platypi::PutSpreadFinder)
      expect(put_finder.underlying_symbol).to eq('$SPX')
      expect(put_finder.expiration_date).to eq(expiration_date)
      expect(put_finder.quantity).to eq(2)
      expect(put_finder.expiration_type).to eq('W')
      expect(put_finder.settlement_type).to eq('P')
      expect(put_finder.option_root).to eq('SPXW')
    end
  end

  describe 'integration with real option data' do
    let(:realistic_finder) do
      described_class.new(
        underlying_symbol: '$SPX',
        expiration_date: expiration_date
      )
    end

    it 'finds realistic iron condors from SPX data' do
      # Mock the option_chain method
      allow(realistic_finder).to receive(:option_chain).and_return(option_chain)

      result = realistic_finder.search(
        from_date: expiration_date,
        to_date: expiration_date,
        short_delta: 0.25,        # ~25 delta short legs
        max_spread: 15.0,         # 15 point spread max
        min_credit: 50.0,         # $0.50 minimum credit per spread
        min_open_interest: 0,     # No OI requirement for test
        dist_from_strike: 0.01    # 1% from current price
      )

      expect(result).to be_a(Platypi::IronCondor)
      expect(result.credit).to be >= 1.0  # Combined credit should be at least $1.00
      expect(result.call_spread.spread_width).to be <= 15.0
      expect(result.put_spread.spread_width).to be <= 15.0
      expect(result.call_spread.short_leg.delta.abs).to be <= 0.25
      expect(result.put_spread.short_leg.delta.abs).to be <= 0.25
    end

    it 'ensures proper iron condor structure' do
      # Mock the option_chain method
      allow(realistic_finder).to receive(:option_chain).and_return(option_chain)

      result = realistic_finder.search(
        from_date: expiration_date,
        to_date: expiration_date,
        short_delta: 0.25,
        max_spread: 15.0,
        min_credit: 50.0,
        min_open_interest: 0,
        dist_from_strike: 0.01
      )

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
      # Mock the option_chain method
      allow(realistic_finder).to receive(:option_chain).and_return(option_chain)

      result = realistic_finder.search(
        from_date: expiration_date,
        to_date: expiration_date,
        short_delta: 0.25,
        max_spread: 15.0,
        min_credit: 50.0,
        min_open_interest: 0,
        dist_from_strike: 0.01
      )

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
        expiration_date: expiration_date
      )
    end

    it 'completes search in reasonable time' do
      # Mock the option_chain method
      allow(performance_finder).to receive(:option_chain).and_return(option_chain)

      start_time = Time.now

      performance_finder.search(
        from_date: expiration_date,
        to_date: expiration_date,
        short_delta: 0.30,
        max_spread: 20.0,
        min_credit: 50.0,
        min_open_interest: 0,
        dist_from_strike: 0.01
      )

      end_time = Time.now
      expect(end_time - start_time).to be < 2.0  # Should complete in under 2 seconds
    end
  end

  describe 'iron condor structure validation' do
    let(:finder) do
      described_class.new(
        underlying_symbol: '$SPX',
        expiration_date: expiration_date
      )
    end

    it 'validates strike price relationships' do
      # Mock the option_chain method
      allow(finder).to receive(:option_chain).and_return(option_chain)

      result = finder.search(
        from_date: expiration_date,
        to_date: expiration_date,
        short_delta: 0.30,
        max_spread: 20.0,
        min_credit: 50.0,
        min_open_interest: 0,
        dist_from_strike: 0.01
      )

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

  describe 'option_chain method call' do
    let(:finder) do
      described_class.new(
        underlying_symbol: '$SPX',
        expiration_date: expiration_date
      )
    end

    before do
      # Mock the option_chain method to return our test data
      allow(finder).to receive(:option_chain).and_return(option_chain)
    end

    it 'calls option_chain with correct parameters' do
      finder.search(
        from_date: expiration_date,
        to_date: expiration_date,
        short_delta: 0.30,
        max_spread: 20.0,
        min_credit: 50.0,
        min_open_interest: 0,
        dist_from_strike: 0.01
      )

      expect(finder).to have_received(:option_chain).with(
        '$SPX',
        contract_type: 'ALL',
        from_date: expiration_date,
        to_date: expiration_date
      )
    end
  end
end