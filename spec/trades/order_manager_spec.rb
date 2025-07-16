require 'spec_helper'

RSpec.describe OptionsTrader::Trades::OrderManager do
  let(:order_manager) { described_class.new }
  let(:order_manager_with_id) { described_class.new(order_id: 'test-order-123') }

  describe '#initialize' do
    it 'initializes with default values' do
      expect(order_manager.order_id).to be_nil
      expect(order_manager.order).to be_nil
      expect(order_manager.order_status).to eq('UNKNOWN')
      expect(order_manager.order_rejects).to eq([])
      expect(order_manager.transactions).to eq([])
    end

    it 'initializes with provided order_id' do
      expect(order_manager_with_id.order_id).to eq('test-order-123')
    end
  end

  describe '#order_id=' do
    it 'sets the order_id' do
      order_manager.order_id = 'new-order-456'
      expect(order_manager.order_id).to eq('new-order-456')
    end
  end

  describe '#order_status' do
    it 'returns UNKNOWN when no order or status is set' do
      expect(order_manager.order_status).to eq('UNKNOWN')
    end

    it 'returns the status from instance variable when set' do
      order_manager.instance_variable_set(:@order_status, 'PENDING')
      expect(order_manager.order_status).to eq('PENDING')
    end
  end

  describe '#opening?' do
    it 'returns true when order_instruction is :open' do
      order_manager.instance_variable_set(:@order_instruction, :open)
      expect(order_manager.opening?).to be true
    end

    it 'returns false when order_instruction is not :open' do
      order_manager.instance_variable_set(:@order_instruction, :exit)
      expect(order_manager.opening?).to be false
    end
  end

  describe '#closing?' do
    it 'returns true when order_instruction is :exit' do
      order_manager.instance_variable_set(:@order_instruction, :exit)
      expect(order_manager.closing?).to be true
    end

    it 'returns false when order_instruction is not :exit' do
      order_manager.instance_variable_set(:@order_instruction, :open)
      expect(order_manager.closing?).to be false
    end
  end

  describe '#accepted?' do
    it 'returns true when order_status is ACCEPTED' do
      order_manager.instance_variable_set(:@order_status, 'ACCEPTED')
      expect(order_manager.accepted?).to be true
    end

    it 'returns false when order_status is not ACCEPTED' do
      order_manager.instance_variable_set(:@order_status, 'PENDING')
      expect(order_manager.accepted?).to be false
    end
  end

  describe '#filled?' do
    it 'returns true when order_status is FILLED' do
      order_manager.instance_variable_set(:@order_status, 'FILLED')
      expect(order_manager.filled?).to be true
    end

    it 'returns false when order_status is not FILLED' do
      order_manager.instance_variable_set(:@order_status, 'PENDING')
      expect(order_manager.filled?).to be false
    end
  end

  describe '#working?' do
    it 'returns true when order_status is WORKING' do
      order_manager.instance_variable_set(:@order_status, 'WORKING')
      expect(order_manager.working?).to be true
    end

    it 'returns true when order_status is PENDING_ACTIVATION' do
      order_manager.instance_variable_set(:@order_status, 'PENDING_ACTIVATION')
      expect(order_manager.working?).to be true
    end

    it 'returns false when order_status is not WORKING or PENDING_ACTIVATION' do
      order_manager.instance_variable_set(:@order_status, 'FILLED')
      expect(order_manager.working?).to be false
    end
  end

  describe '#failed?' do
    it 'returns true for REJECTED status' do
      order_manager.instance_variable_set(:@order_status, 'REJECTED')
      expect(order_manager.failed?).to be true
    end

    it 'returns true for EXPIRED status' do
      order_manager.instance_variable_set(:@order_status, 'EXPIRED')
      expect(order_manager.failed?).to be true
    end

    it 'returns true for CANCELED status' do
      order_manager.instance_variable_set(:@order_status, 'CANCELED')
      expect(order_manager.failed?).to be true
    end

    it 'returns false for other statuses' do
      order_manager.instance_variable_set(:@order_status, 'FILLED')
      expect(order_manager.failed?).to be false
    end
  end

  describe '#to_h' do
    it 'returns a hash with order data' do
      order_manager.instance_variable_set(:@order_id, 'test-123')
      order_manager.instance_variable_set(:@order_instruction, :open)
      order_manager.instance_variable_set(:@order_status, 'FILLED')
      order_manager.instance_variable_set(:@order_price, 1.50)
      order_manager.instance_variable_set(:@order_fees, 0.65)
      order_manager.instance_variable_set(:@order_commission, 0.00)
      order_manager.instance_variable_set(:@order_rejects, [])

      result = order_manager.to_h

      expect(result[:order_id]).to eq('test-123')
      expect(result[:order_instruction]).to eq(:open)
      expect(result[:order_status]).to eq('FILLED')
      expect(result[:order_price]).to eq(1.50)
      expect(result[:order_fees]).to eq(0.65)
      expect(result[:order_commission]).to eq(0.00)
      expect(result[:order_rejects]).to eq([])
    end
  end

  describe '#from_h' do
    it 'populates order data from hash' do
      order_data = {
        order_id: 'test-456',
        order_status: 'ACCEPTED',
        order_instruction: :exit,
        order_price: 2.00,
        order_fees: 0.65,
        order_commission: 0.00,
        order_rejects: ['validation error']
      }

      order_manager.from_h(order_data)

      expect(order_manager.order_id).to eq('test-456')
      expect(order_manager.order_status).to eq('ACCEPTED')
      expect(order_manager.order_instruction).to eq(:exit)
      expect(order_manager.order_price).to eq(2.00)
      expect(order_manager.order_fees).to eq(0.65)
      expect(order_manager.order_commission).to eq(0.00)
      expect(order_manager.order_rejects).to eq(['validation error'])
    end
  end

  describe '#preview_credit_debit' do
    it 'returns order price multiplied by 100' do
      order_manager.instance_variable_set(:@order_price, 1.50)
      expect(order_manager.preview_credit_debit).to eq(150)
    end
  end

  describe '#preview_net_credit_debit' do
    it 'returns net credit after fees and commission' do
      order_manager.instance_variable_set(:@order_price, 1.50)
      order_manager.instance_variable_set(:@order_fees, 0.65)
      order_manager.instance_variable_set(:@order_commission, 0.00)

      expect(order_manager.preview_net_credit_debit).to eq(149.35)
    end
  end
end