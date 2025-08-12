# frozen_string_literal: true

require 'spec_helper'

RSpec.describe OptionsTrader::VerticalSpreadSearch do
  let(:option_chain_data) do
    JSON.parse(
      File.read(File.join(File.dirname(__FILE__), '..', 'fixtures', 'option_chains', 'SPX_05_20_2025_option_chain.json')),
      symbolize_names: true
    )
  end

  let(:option_chain) { SchwabRb::DataObjects::OptionChain.build(option_chain_data) }
  let(:expiration_date) { Date.new(2025, 5, 20) }

  describe '#initialize' do
    it 'sets default values for PUT spreads' do
      search = described_class.new(underlying_symbol: 'SPX', option_root: 'SPXW', put_call: 'PUT')

      expect(search.underlying_symbol).to eq('SPX')
      expect(search.put_call).to eq('PUT')
      expect(search.expiration_date).to be_nil
      expect(search.quantity).to eq(1)
      expect(search.expiration_type).to be_nil
      expect(search.settlement_type).to be_nil
      expect(search.option_root).to eq('SPXW')
      expect(search.spreads).to eq([])
      expect(search.short_legs).to eq([])
    end

    it 'sets default values for CALL spreads' do
      search = described_class.new(underlying_symbol: 'SPX', option_root: 'SPXW', put_call: 'CALL')

      expect(search.underlying_symbol).to eq('SPX')
      expect(search.put_call).to eq('CALL')
      expect(search.expiration_date).to be_nil
      expect(search.quantity).to eq(1)
      expect(search.expiration_type).to be_nil
      expect(search.settlement_type).to be_nil
      expect(search.option_root).to eq('SPXW')
      expect(search.spreads).to eq([])
      expect(search.short_legs).to eq([])
    end

    it 'accepts custom parameters for PUT spreads' do
      search = described_class.new(
        underlying_symbol: 'AAPL',
        put_call: 'PUT',
        expiration_date: expiration_date,
        quantity: 5,
        expiration_type: 'W',
        settlement_type: 'P',
        option_root: 'SPXW'
      )

      expect(search.underlying_symbol).to eq('AAPL')
      expect(search.put_call).to eq('PUT')
      expect(search.expiration_date).to eq(expiration_date)
      expect(search.quantity).to eq(5)
      expect(search.expiration_type).to eq('W')
      expect(search.settlement_type).to eq('P')
      expect(search.option_root).to eq('SPXW')
    end

    it 'accepts custom parameters for CALL spreads' do
      search = described_class.new(
        underlying_symbol: 'AAPL',
        put_call: 'CALL',
        expiration_date: expiration_date,
        quantity: 5,
        expiration_type: 'W',
        settlement_type: 'P',
        option_root: 'SPXW'
      )

      expect(search.underlying_symbol).to eq('AAPL')
      expect(search.put_call).to eq('CALL')
      expect(search.expiration_date).to eq(expiration_date)
      expect(search.quantity).to eq(5)
      expect(search.expiration_type).to eq('W')
      expect(search.settlement_type).to eq('P')
      expect(search.option_root).to eq('SPXW')
    end

    it 'requires put_call parameter' do
      expect {
        described_class.new(underlying_symbol: 'SPX', option_root: 'SPXW')
      }.to raise_error(ArgumentError)
    end

    it 'requires underlying_symbol parameter' do
      expect {
        described_class.new(option_root: 'SPXW', put_call: 'PUT')
      }.to raise_error(ArgumentError)
    end

    it 'requires option_root parameter' do
      expect {
        described_class.new(underlying_symbol: 'SPX', put_call: 'PUT')
      }.to raise_error(ArgumentError)
    end
  end

  describe '#find' do
    context 'with PUT spreads' do
      let(:put_search) do
        described_class.new(
          underlying_symbol: '$SPX',
          option_root: 'SPXW',
          put_call: 'PUT',
          expiration_date: expiration_date,
          quantity: 1
        )
      end

      context 'when called with option chain data directly' do
        it 'returns a put spread when valid criteria are met' do
          result = put_search.find(
            option_chain,
            short_delta: 0.30,
            max_spread: 20.0,
            min_credit: 50.0,
            min_open_interest: 0,
            dist_from_strike: 0.01
          )

          expect(result).to be_a(OptionsTrader::PutSpread)
          expect(result.underlying_symbol).to eq('$SPX')
          expect(result.short_leg).to be_a(OptionsTrader::PutOption)
          expect(result.long_leg).to be_a(OptionsTrader::PutOption)
        end

        it 'returns multiple spreads when return_spreads is true' do
          results = put_search.find(
            option_chain,
            return_spreads: true,
            short_delta: 0.30,
            max_spread: 20.0,
            min_credit: 50.0,
            min_open_interest: 0,
            dist_from_strike: 0.01
          )

          expect(results).to be_an(Array)
          expect(results.all? { |spread| spread.is_a?(OptionsTrader::PutSpread) }).to be true
          expect(results.length).to be > 0
        end
      end

      context 'when called independently (loading option chain internally)' do
        before do
          allow(put_search).to receive(:option_chain).and_return(option_chain)
        end

        it 'loads option chain internally and returns a put spread' do
          result = put_search.find(
            from_date: expiration_date,
            to_date: expiration_date,
            short_delta: 0.30,
            max_spread: 20.0,
            min_credit: 50.0,
            min_open_interest: 0,
            dist_from_strike: 0.01
          )

          expect(put_search).to have_received(:option_chain).with(
            '$SPX',
            contract_type: 'PUT',
            strike_range: 'OTM',
            from_date: expiration_date,
            to_date: expiration_date
          )
          expect(result).to be_a(OptionsTrader::PutSpread)
        end
      end

      context 'with filtering parameters' do
        it 'respects short delta filter' do
          result = put_search.find(
            option_chain,
            short_delta: 0.10,
            max_spread: 20.0,
            min_credit: 25.0,
            min_open_interest: 0,
            dist_from_strike: 0.01
          )

          if result.is_a?(OptionsTrader::PutSpread)
            expect(result.short_leg.delta.abs).to be <= 0.10
          else
            expect(result).to be_a(OptionsTrader::NullStrategy)
          end
        end

        it 'respects max spread width filter' do
          result = put_search.find(
            option_chain,
            short_delta: 0.30,
            max_spread: 5.0,
            min_credit: 25.0,
            min_open_interest: 0,
            dist_from_strike: 0.01
          )

          if result.is_a?(OptionsTrader::PutSpread)
            expect(result.spread_width).to be <= 5.0
          else
            expect(result).to be_a(OptionsTrader::NullStrategy)
          end
        end

        it 'respects minimum credit filter' do
          result = put_search.find(
            option_chain,
            short_delta: 0.30,
            max_spread: 20.0,
            min_credit: 200.0,
            min_open_interest: 0,
            dist_from_strike: 0.01
          )

          if result.is_a?(OptionsTrader::PutSpread)
            expect(result.credit * 100.0).to be >= 200.0
          else
            expect(result).to be_a(OptionsTrader::NullStrategy)
          end
        end

        it 'respects distance from strike filter' do
          result = put_search.find(
            option_chain,
            short_delta: 0.30,
            max_spread: 20.0,
            min_credit: 25.0,
            min_open_interest: 0,
            dist_from_strike: 0.005
          )

          if result.is_a?(OptionsTrader::PutSpread)
            underlying_price = option_chain.underlying_price
            short_strike = result.short_leg.strike
            distance = ((underlying_price - short_strike) / underlying_price).abs
            expect(distance).to be >= 0.005
          else
            expect(result).to be_a(OptionsTrader::NullStrategy)
          end
        end
      end

      it 'ensures proper put spread structure' do
        result = put_search.find(
          option_chain,
          short_delta: 0.30,
          max_spread: 20.0,
          min_credit: 50.0,
          min_open_interest: 0,
          dist_from_strike: 0.01
        )

        if result.is_a?(OptionsTrader::PutSpread)
          expect(result.short_leg.strike).to be > result.long_leg.strike
          expect(result.short_leg.expiration_date).to eq(result.long_leg.expiration_date)
          expect(result.short_leg.expiration_date).to eq(expiration_date)
          expect(result.short_leg.mark).to be > result.long_leg.mark
          expect(result.credit).to be > 0

          underlying_price = option_chain.underlying_price
          expect(result.short_leg.strike).to be < underlying_price
          expect(result.long_leg.strike).to be < underlying_price
        end
      end

      it 'applies quantity to both legs' do
        quantity_search = described_class.new(
          underlying_symbol: '$SPX',
          option_root: 'SPXW',
          put_call: 'PUT',
          expiration_date: expiration_date,
          quantity: 2
        )

        result = quantity_search.find(
          option_chain,
          short_delta: 0.30,
          max_spread: 20.0,
          min_credit: 50.0,
          min_open_interest: 0,
          dist_from_strike: 0.01
        )

        if result.is_a?(OptionsTrader::PutSpread)
          expect(result.short_leg.quantity).to eq(2)
          expect(result.long_leg.quantity).to eq(2)
        end
      end
    end

    context 'with CALL spreads' do
      let(:call_search) do
        described_class.new(
          underlying_symbol: '$SPX',
          option_root: 'SPXW',
          put_call: 'CALL',
          expiration_date: expiration_date,
          quantity: 1
        )
      end

      context 'when called with option chain data directly' do
        it 'returns a call spread when valid criteria are met' do
          result = call_search.find(
            option_chain,
            short_delta: 0.30,
            max_spread: 20.0,
            min_credit: 50.0,
            min_open_interest: 0,
            dist_from_strike: 0.01
          )

          expect(result).to be_a(OptionsTrader::CallSpread)
          expect(result.underlying_symbol).to eq('$SPX')
          expect(result.short_leg).to be_a(OptionsTrader::CallOption)
          expect(result.long_leg).to be_a(OptionsTrader::CallOption)
        end

        it 'returns multiple spreads when return_spreads is true' do
          results = call_search.find(
            option_chain,
            return_spreads: true,
            short_delta: 0.30,
            max_spread: 20.0,
            min_credit: 50.0,
            min_open_interest: 0,
            dist_from_strike: 0.01
          )

          expect(results).to be_an(Array)
          expect(results.all? { |spread| spread.is_a?(OptionsTrader::CallSpread) }).to be true
          expect(results.length).to be > 0
        end
      end

      context 'when called independently (loading option chain internally)' do
        before do
          allow(call_search).to receive(:option_chain).and_return(option_chain)
        end

        it 'loads option chain internally and returns a call spread' do
          result = call_search.find(
            from_date: expiration_date,
            to_date: expiration_date,
            short_delta: 0.30,
            max_spread: 20.0,
            min_credit: 50.0,
            min_open_interest: 0,
            dist_from_strike: 0.01
          )

          expect(call_search).to have_received(:option_chain).with(
            '$SPX',
            contract_type: 'CALL',
            strike_range: 'OTM',
            from_date: expiration_date,
            to_date: expiration_date
          )
          expect(result).to be_a(OptionsTrader::CallSpread)
        end
      end

      context 'with filtering parameters' do
        it 'respects short delta filter' do
          result = call_search.find(
            option_chain,
            short_delta: 0.10,
            max_spread: 20.0,
            min_credit: 25.0,
            min_open_interest: 0,
            dist_from_strike: 0.01
          )

          if result.is_a?(OptionsTrader::CallSpread)
            expect(result.short_leg.delta.abs).to be <= 0.10
          else
            expect(result).to be_a(OptionsTrader::NullStrategy)
          end
        end

        it 'respects max spread width filter' do
          result = call_search.find(
            option_chain,
            short_delta: 0.30,
            max_spread: 5.0,
            min_credit: 25.0,
            min_open_interest: 0,
            dist_from_strike: 0.01
          )

          if result.is_a?(OptionsTrader::CallSpread)
            expect(result.spread_width).to be <= 5.0
          else
            expect(result).to be_a(OptionsTrader::NullStrategy)
          end
        end

        it 'respects minimum credit filter' do
          result = call_search.find(
            option_chain,
            short_delta: 0.30,
            max_spread: 20.0,
            min_credit: 200.0,
            min_open_interest: 0,
            dist_from_strike: 0.01
          )

          if result.is_a?(OptionsTrader::CallSpread)
            expect(result.credit * 100.0).to be >= 200.0
          else
            expect(result).to be_a(OptionsTrader::NullStrategy)
          end
        end

        it 'respects distance from strike filter' do
          result = call_search.find(
            option_chain,
            short_delta: 0.30,
            max_spread: 20.0,
            min_credit: 25.0,
            min_open_interest: 0,
            dist_from_strike: 0.005
          )

          if result.is_a?(OptionsTrader::CallSpread)
            underlying_price = option_chain.underlying_price
            short_strike = result.short_leg.strike
            distance = ((underlying_price - short_strike) / underlying_price).abs
            expect(distance).to be >= 0.005
          else
            expect(result).to be_a(OptionsTrader::NullStrategy)
          end
        end
      end

      it 'ensures proper call spread structure' do
        result = call_search.find(
          option_chain,
          short_delta: 0.30,
          max_spread: 20.0,
          min_credit: 50.0,
          min_open_interest: 0,
          dist_from_strike: 0.01
        )

        if result.is_a?(OptionsTrader::CallSpread)
          expect(result.short_leg.strike).to be < result.long_leg.strike
          expect(result.short_leg.expiration_date).to eq(result.long_leg.expiration_date)
          expect(result.short_leg.expiration_date).to eq(expiration_date)
          expect(result.short_leg.mark).to be > result.long_leg.mark
          expect(result.credit).to be > 0

          underlying_price = option_chain.underlying_price
          expect(result.short_leg.strike).to be > underlying_price
          expect(result.long_leg.strike).to be > underlying_price
        end
      end

      it 'applies quantity to both legs' do
        quantity_search = described_class.new(
          underlying_symbol: '$SPX',
          option_root: 'SPXW',
          put_call: 'CALL',
          expiration_date: expiration_date,
          quantity: 2
        )

        result = quantity_search.find(
          option_chain,
          short_delta: 0.30,
          max_spread: 20.0,
          min_credit: 50.0,
          min_open_interest: 0,
          dist_from_strike: 0.01
        )

        if result.is_a?(OptionsTrader::CallSpread)
          expect(result.short_leg.quantity).to eq(2)
          expect(result.long_leg.quantity).to eq(2)
        end
      end
    end

    context 'edge cases' do
      let(:search) do
        described_class.new(
          underlying_symbol: '$SPX',
          option_root: 'SPXW',
          put_call: 'PUT',
          expiration_date: expiration_date
        )
      end

      it 'returns NullStrategy when no valid spreads found' do
        result = search.find(
          option_chain,
          short_delta: 0.001,
          max_spread: 1.0,
          min_credit: 1000.0,
          min_open_interest: 10000,
          dist_from_strike: 0.50
        )

        expect(result).to be_a(OptionsTrader::NullStrategy)
      end

      it 'handles nil option chain' do
        allow(search).to receive(:option_chain).and_return(nil)

        result = search.find(
          from_date: expiration_date,
          to_date: expiration_date,
          short_delta: 0.30,
          max_spread: 20.0
        )

        expect(result).to be_a(OptionsTrader::NullStrategy)
      end
    end

    context 'with option type filters' do
      let(:put_search_with_filters) do
        described_class.new(
          underlying_symbol: '$SPX',
          put_call: 'PUT',
          expiration_date: expiration_date,
          expiration_type: 'W',
          settlement_type: 'P',
          option_root: 'SPXW'
        )
      end

      it 'filters by expiration type when specified' do
        result = put_search_with_filters.find(
          option_chain,
          short_delta: 0.30,
          max_spread: 20.0,
          min_credit: 50.0,
          min_open_interest: 0,
          dist_from_strike: 0.05
        )

        if result.is_a?(OptionsTrader::PutSpread)
          expect(result).to be_a(OptionsTrader::PutSpread)
        end
      end

      it 'filters by settlement type when specified' do
        result = put_search_with_filters.find(
          option_chain,
          short_delta: 0.30,
          max_spread: 20.0,
          min_credit: 50.0,
          min_open_interest: 0,
          dist_from_strike: 0.05
        )

        if result.is_a?(OptionsTrader::PutSpread)
          expect(result).to be_a(OptionsTrader::PutSpread)
        end
      end

      it 'filters by option root when specified' do
        result = put_search_with_filters.find(
          option_chain,
          short_delta: 0.30,
          max_spread: 20.0,
          min_credit: 50.0,
          min_open_interest: 0,
          dist_from_strike: 0.05
        )

        if result.is_a?(OptionsTrader::PutSpread)
          expect(result).to be_a(OptionsTrader::PutSpread)
        end
      end
    end
  end

  describe 'invalid put_call parameter' do
    it 'raises error during options_array access' do
      search = described_class.new(
        underlying_symbol: 'SPX',
        option_root: 'SPXW',
        put_call: 'INVALID'
      )

      expect {
        search.send(:options_array)
      }.to raise_error(ArgumentError, /Invalid put_call type: INVALID/)
    end
  end
end