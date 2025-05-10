# frozen_string_literal: true

require 'rspec'
require_relative '../../mixins/orderable'
require_relative '../../mixins/schwab/data_objects/order'

RSpec.describe Orderable do
  # Create a test class that includes the Orderable mixin
  let(:test_class) do
    Class.new do
      include Orderable

      def quantity
        1
      end

      def credit_debit
        1.25
      end
    end
  end

  let(:orderable_instance) { test_class.new }
  let(:test_date) { Date.today }
  let(:test_time) { DateTime.now }

  before do
    orderable_instance.initialize_orderable

    # Stub Schwab methods
    allow(orderable_instance).to receive(:build_and_preview_order).and_return(
      instance_double('OrderPreview',
                      accepted?: true,
                      fees: 1.14,
                      commission: 1.30,
                      order_strategy: instance_double('OrderStrategy', status: 'WORKING'),
                      order_validation_result: instance_double('ValidationResult', rejects: []))
    )

    working_order = DataObjects::Order.build({
                                               orderId: '123456',
                                               status: 'WORKING',
                                               price: 1.25,
                                               enteredTime: test_time.iso8601,
                                               duration: 'DAY',
                                               orderType: 'LIMIT',
                                               complexOrderStrategyType: 'NONE',
                                               quantity: 1,
                                               filledQuantity: 0,
                                               remainingQuantity: 1,
                                               orderStrategyType: 'SINGLE',
                                               closeTime: nil,
                                               orderLegCollection: [],
                                               orderActivityCollection: []
                                             })

    replacement_order = DataObjects::Order.build({
                                                   orderId: '789012',
                                                   status: 'WORKING',
                                                   price: 1.35,
                                                   enteredTime: test_time.iso8601,
                                                   fees: 1.14,
                                                   commission: 1.30,
                                                   duration: 'DAY',
                                                   orderType: 'LIMIT',
                                                   complexOrderStrategyType: 'NONE',
                                                   quantity: 1,
                                                   filledQuantity: 0,
                                                   remainingQuantity: 1,
                                                   orderStrategyType: 'SINGLE',
                                                   closeTime: nil,
                                                   orderLegCollection: [],
                                                   orderActivityCollection: []
                                                 })

    filled_order = DataObjects::Order.build({
                                              orderId: '123456',
                                              status: 'FILLED',
                                              price: 1.25,
                                              enteredTime: test_time.iso8601,
                                              fees: 1.14,
                                              commission: 1.30,
                                              duration: 'DAY',
                                              orderType: 'LIMIT',
                                              complexOrderStrategyType: 'NONE',
                                              quantity: 1,
                                              filledQuantity: 1,
                                              remainingQuantity: 0,
                                              orderStrategyType: 'SINGLE',
                                              closeTime: nil,
                                              orderLegCollection: [],
                                              orderActivityCollection: []
                                            })

    allow(orderable_instance).to receive(:build_and_place_order).and_return(working_order)
    allow(orderable_instance).to receive(:build_and_replace_order).and_return(replacement_order)
    allow(orderable_instance).to receive(:get_order).and_return(filled_order)
    allow(orderable_instance).to receive(:cancel_order).and_return(true)
  end

  describe '#initialize_orderable' do
    it 'initializes empty transactions array' do
      expect(orderable_instance.transactions).to eq([])
    end
  end

  describe '#send' do
    it 'sends an order and updates order details' do
      orderable_instance.send

      expect(orderable_instance.order_id).to eq('123456')
      expect(orderable_instance.order_status).to eq('WORKING')
      expect(orderable_instance.order).not_to be_nil
    end
  end

  describe '#replace' do
    it 'replaces an order and updates order details' do
      # First place an order
      orderable_instance.send
      expect(orderable_instance.order_id).to eq('123456')

      # Replace the order
      orderable_instance.replace

      expect(orderable_instance.order_id).to eq('789012')
      expect(orderable_instance.order_status).to eq('WORKING')
      expect(orderable_instance.order.price).to eq(1.35)
    end

    it 'returns nil if no order_id exists' do
      orderable_instance.order_id = nil
      expect(orderable_instance.replace).to be_nil
    end
  end

  describe '#check_order_status' do
    it 'updates the order status and filled order details when order is filled' do
      # First place an order
      orderable_instance.send
      expect(orderable_instance.order_id).to eq('123456')
      expect(orderable_instance.order_status).to eq('WORKING')

      # Check status - should detect it's filled
      orderable_instance.check_order_status

      # Check that order status is updated
      expect(orderable_instance.order_status).to eq('FILLED')

      # Check that filled order is set
      expect(orderable_instance.filled_order).not_to be_nil
      expect(orderable_instance.filled_order_id).to eq('123456')
      expect(orderable_instance.filled_order_status).to eq('FILLED')
      expect(orderable_instance.filled_order_price).to eq(1.25)
      expect(orderable_instance.filled_order_date).to eq(test_time.to_date)

      # Check that helper methods work
      expect(orderable_instance.filled_open_date).to eq(test_time.to_date)
      expect(orderable_instance.filled_open_credit_debit).to eq(1.25)
      expect(orderable_instance.filled_open_fees).to be_nil
      expect(orderable_instance.filled_open_commission).to be_nil
    end

    it 'clears order_id when order is rejected' do
      # Place an order
      orderable_instance.send
      expect(orderable_instance.order_id).to eq('123456')

      # Override the get_order stub for this test
      rejected_order = DataObjects::Order.build({
                                                  orderId: '123456',
                                                  status: 'REJECTED',
                                                  price: nil,
                                                  enteredTime: nil,
                                                  duration: 'DAY',
                                                  orderType: 'LIMIT',
                                                  complexOrderStrategyType: 'NONE',
                                                  quantity: 1,
                                                  filledQuantity: 0,
                                                  remainingQuantity: 1,
                                                  orderStrategyType: 'SINGLE',
                                                  closeTime: nil,
                                                  orderLegCollection: [],
                                                  orderActivityCollection: []
                                                })
      allow(orderable_instance).to receive(:get_order).and_return(rejected_order)

      # Check status
      orderable_instance.check_order_status

      expect(orderable_instance.order_id).to be_nil
      expect(orderable_instance.order_status).to eq('REJECTED')
    end

    it 'returns nil if no order_id exists' do
      orderable_instance.order_id = nil
      expect(orderable_instance.check_order_status).to be_nil
    end
  end

  describe '#cancel' do
    it 'cancels an order and clears order details' do
      # Place an order
      orderable_instance.send
      expect(orderable_instance.order_id).to eq('123456')

      # Cancel it
      orderable_instance.cancel

      expect(orderable_instance.order_id).to be_nil
      expect(orderable_instance.order_status).to be_nil
      expect(orderable_instance.order).to be_nil
    end

    it 'returns nil if no order_id exists' do
      orderable_instance.order_id = nil
      expect(orderable_instance.cancel).to be_nil
    end
  end

  describe '#filled?' do
    it 'returns true when current order status is FILLED' do
      orderable_instance.instance_variable_set(:@order_status, 'FILLED')
      expect(orderable_instance.filled?).to be true
    end

    it 'returns true when filled_order status is FILLED' do
      filled_order = DataObjects::Order.build({
                                                orderId: '123456',
                                                status: 'FILLED',
                                                price: 1.25,
                                                enteredTime: DateTime.now.iso8601
                                              })
      orderable_instance.instance_variable_set(:@filled_order, filled_order)
      expect(orderable_instance.filled?).to be true
    end

    it 'returns false when neither is FILLED' do
      orderable_instance.instance_variable_set(:@order_status, 'WORKING')
      orderable_instance.instance_variable_set(:@filled_order, nil)
      expect(orderable_instance.filled?).to be false
    end
  end

  describe '#working?' do
    it 'returns true when order status is WORKING' do
      orderable_instance.instance_variable_set(:@order_status, 'WORKING')
      expect(orderable_instance.working?).to be true
    end

    it 'returns false when order status is not WORKING' do
      orderable_instance.instance_variable_set(:@order_status, 'FILLED')
      expect(orderable_instance.working?).to be false
    end
  end

  describe '#failed?' do
    it 'returns true when order status is REJECTED' do
      orderable_instance.instance_variable_set(:@order_status, 'REJECTED')
      expect(orderable_instance.failed?).to be true
    end

    it 'returns true when order status is EXPIRED' do
      orderable_instance.instance_variable_set(:@order_status, 'EXPIRED')
      expect(orderable_instance.failed?).to be true
    end

    it 'returns true when order status is CANCELED' do
      orderable_instance.instance_variable_set(:@order_status, 'CANCELED')
      expect(orderable_instance.failed?).to be true
    end

    it 'returns false when order status is not in the failed list' do
      orderable_instance.instance_variable_set(:@order_status, 'WORKING')
      expect(orderable_instance.failed?).to be false
    end
  end
end
