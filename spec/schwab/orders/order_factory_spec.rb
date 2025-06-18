# frozen_string_literal: true

require 'spec_helper'
require 'schwab_rb'

RSpec.describe Platypi::Schwab::Orders::OrderFactory do
  describe '.build' do
    let(:account_number) { '123456789' }
    let(:quantity) { 1 }
    let(:options) { { account_number: account_number, quantity: quantity } }
    let(:exit_options) { { account_number: account_number, quantity: quantity, order_instruction: :exit } }
    let(:order_builder) { instance_double(SchwabRb::Orders::Builder) }

    context 'with an iron condor trade' do
      let(:put_short) { instance_double('Platypi::PutOption', symbol: 'SPY_P410') }
      let(:put_long) { instance_double('Platypi::PutOption', symbol: 'SPY_P400') }
      let(:call_short) { instance_double('Platypi::CallOption', symbol: 'SPY_C440') }
      let(:call_long) { instance_double('Platypi::CallOption', symbol: 'SPY_C450') }

      let(:put_spread) { instance_double('Platypi::PutSpread', short_leg: put_short, long_leg: put_long) }
      let(:call_spread) { instance_double('Platypi::CallSpread', short_leg: call_short, long_leg: call_long) }

      let(:iron_condor) do
        instance_double(
          'Platypi::IronCondor',
          class: class_double('Platypi::IronCondor', name: 'Platypi::IronCondor'),
          put_spread: put_spread,
          call_spread: call_spread,
          credit: 1.25
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
      let(:short_leg) { instance_double('Platypi::CallOption', symbol: 'SPY_C440') }
      let(:long_leg) { instance_double('Platypi::CallOption', symbol: 'SPY_C450') }

      let(:call_spread) do
        instance_double(
          'Platypi::CallSpread',
          class: class_double('Platypi::CallSpread', name: 'Platypi::CallSpread'),
          short_leg: short_leg,
          long_leg: long_leg,
          credit: 0.75
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
          'Platypi::CallOption',
          class: class_double('Platypi::CallOption', name: 'Platypi::CallOption')
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