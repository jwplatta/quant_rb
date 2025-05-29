# frozen_string_literal: true

require 'spec_helper'
require 'schwab_rb'
require_relative '../../../../mixins/schwab/orders/order_factory'
require_relative '../../../../services/trades/iron_condor'
require_relative '../../../../services/trades/call_spread'
require_relative '../../../../services/trades/put_spread'
require_relative '../../../../services/trades/call_option'
require_relative '../../../../services/trades/put_option'

RSpec.describe OrderFactory do
  describe '.strategy_type' do
    let(:iron_condor) { instance_double('Services::Trades::IronCondor', class: class_double('Services::Trades::IronCondor', name: 'Services::Trades::IronCondor')) }
    let(:call_spread) { instance_double('Services::Trades::CallSpread', class: class_double('Services::Trades::CallSpread', name: 'Services::Trades::CallSpread')) }
    let(:put_spread) { instance_double('Services::Trades::PutSpread', class: class_double('Services::Trades::PutSpread', name: 'Services::Trades::PutSpread')) }
    let(:call_option) { instance_double('Services::Trades::CallOption', class: class_double('Services::Trades::CallOption', name: 'Services::Trades::CallOption')) }
    let(:put_option) { instance_double('Services::Trades::PutOption', class: class_double('Services::Trades::PutOption', name: 'Services::Trades::PutOption')) }
    let(:unknown_trade) { instance_double('UnknownTrade', class: class_double('UnknownTrade', name: 'UnknownTrade')) }

    it 'returns IRON_CONDOR for iron condor trades' do
      expect(described_class.strategy_type(iron_condor)).to eq('IRON_CONDOR')
    end

    it 'returns VERTICAL for call spread trades' do
      expect(described_class.strategy_type(call_spread)).to eq('VERTICAL')
    end

    it 'returns VERTICAL for put spread trades' do
      expect(described_class.strategy_type(put_spread)).to eq('VERTICAL')
    end

    it 'returns SINGLE for call option trades' do
      expect(described_class.strategy_type(call_option)).to eq('SINGLE')
    end

    it 'returns SINGLE for put option trades' do
      expect(described_class.strategy_type(put_option)).to eq('SINGLE')
    end

    it 'raises ArgumentError for unsupported trade types' do
      expect {
        described_class.strategy_type(unknown_trade)
      }.to raise_error(ArgumentError, "Unsupported trade type: UnknownTrade")
    end
  end

  describe '.build' do
    let(:account_number) { '123456789' }
    let(:quantity) { 1 }
    let(:options) { { account_number: account_number, quantity: quantity } }
    let(:exit_options) { { account_number: account_number, quantity: quantity, order_instruction: :exit } }
    let(:order_builder) { instance_double(SchwabRb::Orders::Builder) }

    context 'with an iron condor trade' do
      let(:put_short) { instance_double('Services::Trades::PutOption', symbol: 'SPY_P410') }
      let(:put_long) { instance_double('Services::Trades::PutOption', symbol: 'SPY_P400') }
      let(:call_short) { instance_double('Services::Trades::CallOption', symbol: 'SPY_C440') }
      let(:call_long) { instance_double('Services::Trades::CallOption', symbol: 'SPY_C450') }

      let(:put_spread) { instance_double('Services::Trades::PutSpread', short_leg: put_short, long_leg: put_long) }
      let(:call_spread) { instance_double('Services::Trades::CallSpread', short_leg: call_short, long_leg: call_long) }

      let(:iron_condor) do
        instance_double(
          'Services::Trades::IronCondor',
          class: class_double('Services::Trades::IronCondor', name: 'Services::Trades::IronCondor'),
          put_spread: put_spread,
          call_spread: call_spread,
          credit_debit: 1.25
        )
      end

      before do
        # Create a concrete builder object that can be returned
        allow(IronCondorOrder).to receive(:build).and_return(order_builder)
      end

      it 'delegates to IronCondorOrder.build' do
        described_class.build(iron_condor, **options)
        expect(IronCondorOrder).to have_received(:build).with(iron_condor, hash_including(account_number: account_number, quantity: quantity))
      end

      it 'handles exit orders' do
        described_class.build(iron_condor, **exit_options)
        expect(IronCondorOrder).to have_received(:build).with(iron_condor, hash_including(account_number: account_number, quantity: quantity, order_instruction: :exit))
      end
    end

    context 'with a vertical spread trade' do
      let(:short_leg) { instance_double('Services::Trades::CallOption', symbol: 'SPY_C440') }
      let(:long_leg) { instance_double('Services::Trades::CallOption', symbol: 'SPY_C450') }

      let(:call_spread) do
        instance_double(
          'Services::Trades::CallSpread',
          class: class_double('Services::Trades::CallSpread', name: 'Services::Trades::CallSpread'),
          short_leg: short_leg,
          long_leg: long_leg,
          credit_debit: 0.75
        )
      end

      before do
        # Create a concrete builder object that can be returned
        allow(VerticalOrder).to receive(:build).and_return(order_builder)
      end

      it 'delegates to VerticalOrder.build' do
        described_class.build(call_spread, **options)
        expect(VerticalOrder).to have_received(:build).with(call_spread, hash_including(account_number: account_number, quantity: quantity))
      end

      it 'handles exit orders' do
        described_class.build(call_spread, **exit_options)
        expect(VerticalOrder).to have_received(:build).with(call_spread, hash_including(account_number: account_number, quantity: quantity, order_instruction: :exit))
      end
    end

    context 'with an unsupported trade type' do
      let(:single_option) do
        instance_double(
          'Services::Trades::CallOption',
          class: class_double('Services::Trades::CallOption', name: 'Services::Trades::CallOption')
        )
      end

      it 'raises an error for unsupported trade strategies' do
        expect {
          described_class.build(single_option, **options)
        }.to raise_error('Unsupported trade strategy')
      end
    end
  end
end