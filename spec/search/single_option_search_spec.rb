# frozen_string_literal: true

require 'spec_helper'

RSpec.describe OptionsTrader::SingleOptionSearch do
  let(:option_chain_data) do
    JSON.parse(
      File.read(File.join(File.dirname(__FILE__), '..', 'fixtures', 'option_chains', 'SPX_05_20_2025_option_chain.json')),
      symbolize_names: true
    )
  end

  let(:option_chain) { SchwabRb::DataObjects::OptionChain.build(option_chain_data) }
  let(:expiration_date) { Date.new(2025, 5, 20) }

  describe '#initialize' do
    it 'sets default values' do
      search = described_class.new(underlying_symbol: 'SPX', put_call: 'PUT')

      expect(search.underlying_symbol).to eq('SPX')
      expect(search.put_call).to eq('PUT')
      expect(search.quantity).to eq(1)
    end

    it 'requires put_call and underlying_symbol parameters' do
      expect {
        described_class.new(underlying_symbol: 'SPX')
      }.to raise_error(ArgumentError)

      expect {
        described_class.new(put_call: 'PUT')
      }.to raise_error(ArgumentError)
    end
  end

  describe '#find' do
    context 'with PUT options' do
      let(:put_search) do
        described_class.new(
          underlying_symbol: '$SPX',
          put_call: 'PUT',
          expiration_date: expiration_date
        )
      end

      it 'returns a put option when valid criteria are met' do
        result = put_search.find(
          option_chain,
          max_delta: 0.30,
          min_open_interest: 0,
          dist_from_strike: 0.01
        )

        expect(result).to be_a(OptionsTrader::PutOption)
        expect(result.symbol).to include('SPX')
        expect(result.strike).to be > 0
        expect(result.mark).to be > 0
      end

      it 'returns multiple options when return_all is true' do
        results = put_search.find(
          option_chain,
          return_all: true,
          max_delta: 0.30,
          min_open_interest: 0,
          dist_from_strike: 0.01
        )

        expect(results).to be_an(Array)
        expect(results.all? { |option| option.is_a?(OptionsTrader::PutOption) }).to be true
        expect(results.length).to be > 0
      end

      it 'respects filtering parameters' do
        result = put_search.find(
          option_chain,
          max_delta: 0.10,
          min_open_interest: 0,
          dist_from_strike: 0.01
        )

        if result.is_a?(OptionsTrader::PutOption)
          expect(result.delta.abs).to be <= 0.10
        else
          expect(result).to be_a(OptionsTrader::NullStrategy)
        end
      end
    end

    context 'with CALL options' do
      let(:call_search) do
        described_class.new(
          underlying_symbol: '$SPX',
          put_call: 'CALL',
          expiration_date: expiration_date
        )
      end

      it 'returns a call option when valid criteria are met' do
        result = call_search.find(
          option_chain,
          max_delta: 0.30,
          min_open_interest: 0,
          dist_from_strike: 0.01
        )

        expect(result).to be_a(OptionsTrader::CallOption)
        expect(result.symbol).to include('SPX')
        expect(result.strike).to be > 0
        expect(result.mark).to be > 0
      end

      it 'respects filtering parameters' do
        result = call_search.find(
          option_chain,
          max_delta: 0.10,
          min_open_interest: 0,
          dist_from_strike: 0.01
        )

        if result.is_a?(OptionsTrader::CallOption)
          expect(result.delta.abs).to be <= 0.10
        else
          expect(result).to be_a(OptionsTrader::NullStrategy)
        end
      end
    end

    context 'edge cases' do
      let(:search) do
        described_class.new(
          underlying_symbol: '$SPX',
          put_call: 'PUT',
          expiration_date: expiration_date
        )
      end

      it 'returns NullStrategy when no valid options found' do
        result = search.find(
          option_chain,
          max_delta: 0.001,
          min_open_interest: 10000,
          dist_from_strike: 0.50
        )

        expect(result).to be_a(OptionsTrader::NullStrategy)
      end

      it 'returns NullStrategy when expiration_date is nil' do
        no_date_search = described_class.new(
          underlying_symbol: '$SPX',
          put_call: 'PUT'
        )

        result = no_date_search.find(option_chain)

        expect(result).to be_a(OptionsTrader::NullStrategy)
      end
    end

    it 'loads option chain internally when not provided' do
      search = described_class.new(
        underlying_symbol: '$SPX',
        put_call: 'PUT',
        expiration_date: expiration_date
      )

      allow(search).to receive(:option_chain).and_return(option_chain)

      result = search.find(
        from_date: expiration_date,
        to_date: expiration_date,
        max_delta: 0.30
      )

      expect(search).to have_received(:option_chain)
      expect(result).to be_a(OptionsTrader::PutOption)
    end
  end

  describe 'invalid put_call parameter' do
    it 'raises error during options_array access' do
      search = described_class.new(
        underlying_symbol: 'SPX',
        put_call: 'INVALID'
      )

      expect {
        search.send(:options_array)
      }.to raise_error(ArgumentError, /Invalid put_call type: INVALID/)
    end
  end
end