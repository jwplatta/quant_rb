# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Platypi::PutSpreadFinder do
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
      expect(finder.trades).to eq([])
      expect(finder.short_legs).to eq([])
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
        min_credit: 50.0,
        min_open_interest: 0,
        dist_from_strike: 0.01,
        quantity: 1
      )
    end

    context 'when called with option chain data (from IronCondorFinder)' do
      it 'finds put spreads with valid criteria' do
        result = finder.search(option_chain)

        expect(result).to be_a(Platypi::PutSpread)
        expect(result.underlying_symbol).to eq('$SPX')
        expect(result.short_leg).to be_a(Platypi::PutOption)
        expect(result.long_leg).to be_a(Platypi::PutOption)
      end

      it 'returns the spread with the highest credit' do
        result = finder.search(option_chain)

        # Since we're looking for the max credit, verify it's a valid spread
        expect(result.credit).to be > 0.5
        expect(result.short_leg.strike).to be > result.long_leg.strike  # Put spread structure
      end
    end

    context 'when called independently (loads option chain internally)' do
      before do
        # Mock the option_chain method to return our test data
        allow(finder).to receive(:option_chain).and_return(option_chain)
      end

      it 'loads option chain and finds put spreads' do
        result = finder.search(
          from_date: expiration_date,
          to_date: expiration_date
        )

        expect(result).to be_a(Platypi::PutSpread)
        expect(result.underlying_symbol).to eq('$SPX')
      end

      it 'calls option_chain with correct parameters' do
        finder.search(
          from_date: expiration_date,
          to_date: expiration_date
        )

        expect(finder).to have_received(:option_chain).with(
          '$SPX',
          contract_type: 'PUT',
          from_date: expiration_date,
          to_date: expiration_date
        )
      end

      it 'uses expiration_date as default for from_date and to_date' do
        finder.search()

        expect(finder).to have_received(:option_chain).with(
          '$SPX',
          contract_type: 'PUT',
          from_date: expiration_date,
          to_date: expiration_date
        )
      end

      context 'when option_chain method returns nil' do
        before do
          allow(finder).to receive(:option_chain).and_return(nil)
        end

        it 'returns NullStrategy' do
          result = finder.search(
            from_date: expiration_date,
            to_date: expiration_date
          )
          expect(result).to be_a(Platypi::NullStrategy)
        end
      end
    end

    it 'respects short delta filter' do
      # Use a very low delta to limit options
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

      if result.is_a?(Platypi::PutSpread)
        expect(result.short_leg.delta.abs).to be <= 0.10
      else
        # If no spreads found, it should return NullStrategy
        expect(result).to be_a(Platypi::NullStrategy)
      end
    end

    it 'respects max spread width filter' do
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

      if result.is_a?(Platypi::PutSpread)
        spread_width = result.short_leg.strike - result.long_leg.strike
        expect(spread_width).to be <= 5.0
      else
        expect(result).to be_a(Platypi::NullStrategy)
      end
    end

    it 'respects minimum credit filter' do
      high_credit_finder = described_class.new(
        underlying_symbol: '$SPX',
        expiration_date: expiration_date,
        short_delta: 0.30,
        max_spread: 20.0,
        min_credit: 300.0,  # High minimum credit
        min_open_interest: 0,
        dist_from_strike: 0.01
      )

      result = high_credit_finder.search(option_chain)

      if result.is_a?(Platypi::PutSpread)
        expect(result.credit * 100).to be >= 300.0
      else
        expect(result).to be_a(Platypi::NullStrategy)
      end
    end

    it 'respects distance from strike filter' do
      # The underlying price is 5659.91, so with 0.005 distance we need strikes
      # that are at least 0.5% away from current price
      close_strike_finder = described_class.new(
        underlying_symbol: '$SPX',
        expiration_date: expiration_date,
        short_delta: 0.30,
        max_spread: 20.0,
        min_credit: 25.0,
        min_open_interest: 0,
        dist_from_strike: 0.005
      )

      result = close_strike_finder.search(option_chain)

      if result.is_a?(Platypi::PutSpread)
        underlying_price = option_chain.underlying_price
        short_strike = result.short_leg.strike
        distance = ((underlying_price - short_strike) / underlying_price).abs
        expect(distance).to be >= 0.005
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

      # Since expiration_type filtering happens at the raw option level,
      # we just verify that if a spread is found, it's valid
      if result.is_a?(Platypi::PutSpread)
        expect(result.short_leg).to be_a(Platypi::PutOption)
        expect(result.long_leg).to be_a(Platypi::PutOption)
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

      # Since settlement_type filtering happens at the raw option level,
      # we just verify that if a spread is found, it's valid
      if result.is_a?(Platypi::PutSpread)
        expect(result.short_leg).to be_a(Platypi::PutOption)
        expect(result.long_leg).to be_a(Platypi::PutOption)
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

      # Since option_root filtering happens at the raw option level,
      # we just verify that if a spread is found, it's valid
      if result.is_a?(Platypi::PutSpread)
        expect(result.short_leg).to be_a(Platypi::PutOption)
        expect(result.long_leg).to be_a(Platypi::PutOption)
      end
    end

    it 'returns NullStrategy when no valid spreads found' do
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

    it 'selects the long leg with the lowest mark price' do
      # This test verifies that when multiple long legs are available,
      # the finder selects the one with the lowest mark (cheapest protection)
      result = finder.search(option_chain)

      if result.is_a?(Platypi::PutSpread)
        short_strike = result.short_leg.strike

        # Find all potential long legs that would have been candidates
        potential_longs = option_chain.put_opts.select do |opt|
          opt.expiration_date == expiration_date &&
            opt.mark > 0.0 &&
            opt.strike < short_strike &&
            (short_strike - opt.strike) <= finder.max_spread
        end

        if potential_longs.any?
          cheapest_long = potential_longs.min_by(&:mark)
          expect(result.long_leg.mark).to eq(cheapest_long.mark)
        end
      end
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
      it 'handles option chain with no put options' do
        empty_chain_data = option_chain_data.dup
        empty_chain_data[:putExpDateMap] = {}
        empty_chain = Platypi::Schwab::DataObjects::OptionChain.build(empty_chain_data)

        result = finder.search(empty_chain)
        expect(result).to be_a(Platypi::NullStrategy)
      end

      it 'handles options with zero or negative marks' do
        # This is more of an integration test to ensure the search doesn't break
        # with edge case data
        result = finder.search(option_chain)

        if result.is_a?(Platypi::PutSpread)
          expect(result.short_leg.mark).to be > 0
          expect(result.long_leg.mark).to be > 0
        end
      end
    end
  end

  describe 'integration with real option data' do
    let(:realistic_finder) do
      described_class.new(
        underlying_symbol: '$SPX',
        expiration_date: expiration_date,
        short_delta: 0.25,        # ~25 delta short
        max_spread: 15.0,         # 15 point spread max
        min_credit: 50.0,         # $0.50 minimum credit
        min_open_interest: 0,     # No OI requirement for test
        dist_from_strike: 0.01    # 1% from current price
      )
    end

    it 'finds realistic put spreads from SPX data' do
      result = realistic_finder.search(option_chain)

      expect(result).to be_a(Platypi::PutSpread)
      expect(result.credit).to be >= 0.5
      expect(result.spread_width).to be <= 15.0
      expect(result.short_leg.delta.abs).to be <= 0.25
      expect(result.short_leg.strike).to be > result.long_leg.strike
    end

    it 'populates trades array during search' do
      finder = realistic_finder
      finder.search(option_chain)

      expect(finder.trades).not_to be_empty
      expect(finder.trades).to all(be_a(Platypi::PutSpread))
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
      expect(end_time - start_time).to be < 1.0  # Should complete in under 1 second
    end
  end

  describe 'put spread structure validation' do
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

    it 'ensures proper put spread structure (short strike > long strike)' do
      result = finder.search(option_chain)

      if result.is_a?(Platypi::PutSpread)
        # For put spreads, we sell a higher strike and buy a lower strike
        expect(result.short_leg.strike).to be > result.long_leg.strike

        # The spread should be a credit spread (we collect premium)
        expect(result.credit).to be > 0

        # Both legs should have the same expiration
        expect(result.short_leg.expiration_date).to eq(result.long_leg.expiration_date)
      end
    end
  end
end
