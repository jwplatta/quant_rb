# frozen_string_literal: true

require 'spec_helper'
require_relative '../../bots/trade_event'

RSpec.describe TradeEvent do
  describe '#initialize' do
    context 'with only event type' do
      it 'creates an event with empty payload' do
        event = described_class.new(:test_event)

        expect(event.type).to eq(:test_event)
        expect(event.payload).to eq({})
      end
    end

    context 'with event type and payload' do
      it 'creates an event with the specified payload' do
        payload = { trade: double('Trade'), value: 100 }
        event = described_class.new(:test_event, payload)

        expect(event.type).to eq(:test_event)
        expect(event.payload).to eq(payload)
      end
    end
  end

  describe 'attribute access' do
    it 'provides read access to type and payload' do
      payload = { value: 'test' }
      event = described_class.new(:test_event, payload)

      expect(event.type).to eq(:test_event)
      expect(event.payload).to eq(payload)
    end

    it 'does not allow modification of attributes' do
      event = described_class.new(:test_event)

      expect { event.type = :new_type }.to raise_error(NoMethodError)
      expect { event.payload = {} }.to raise_error(NoMethodError)
    end
  end
end
