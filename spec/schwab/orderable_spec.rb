# frozen_string_literal: true

require 'rspec'
require 'ostruct'

RSpec.describe Platypi::Orderable do
  let(:test_class) do
    Class.new do
      include Platypi::Orderable

      def quantity
        1
      end

      def credit
        1.25
      end

      def type
        'callspread'
      end

      def short_leg
        OpenStruct.new(symbol: 'SPX251219C05900')
      end

      def long_leg
        OpenStruct.new(symbol: 'SPX251219C06000')
      end

      def debit
        -0.50
      end
    end
  end

  let(:orderable_instance) { test_class.new }
  let(:test_date) { Date.today }
  let(:test_time) { DateTime.now }

  # Mock the SchwabRb client
  let(:mock_client) { double('SchwabRb::Client') }

  before do
    # Stub the client method to return our mock client (from Schwab module)
    allow(orderable_instance).to receive(:client).and_return(mock_client)
    allow(orderable_instance).to receive(:account_hash).and_return('ABC123XYZ')

    orderable_instance.initialize_orderable

    allow(orderable_instance).to receive(:build_and_preview_order).and_return(
      instance_double('OrderPreview',
                      accepted?: true,
                      fees: 1.14,
                      commission: 1.30,
                      price: 1.25,
                      status: 'ACCEPTED',
                      order_id: 'preview123',
                      entered_time: test_time,
                      order_validation_result: instance_double('ValidationResult', rejects: []))
    )

    working_order = Platypi::Schwab::DataObjects::Order.build({
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

    replacement_order = Platypi::Schwab::DataObjects::Order.build({
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

    filled_order = Platypi::Schwab::DataObjects::Order.build({
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
    it 'initializes empty transactions array and nil order fields' do
      expect(orderable_instance.transactions).to eq([])
      expect(orderable_instance.order).to be_nil
      expect(orderable_instance.order_id).to be_nil
      expect(orderable_instance.filled_order).to be_nil
    end
  end

  describe '#preview' do
    it 'previews an order and sets preview attributes' do
      orderable_instance.preview(orderable_instance)

      expect(orderable_instance.order_preview).not_to be_nil
      expect(orderable_instance.order_preview_id).to eq('preview123')
      expect(orderable_instance.order_preview_price).to eq(1.25)
      expect(orderable_instance.order_preview_fees).to eq(1.14)
      expect(orderable_instance.order_preview_commission).to eq(1.30)
      expect(orderable_instance.order_preview_status).to eq('ACCEPTED')
      expect(orderable_instance.order_preview_rejects).to eq([])
    end

    it 'accepts order_instruction parameter' do
      expect(orderable_instance).to receive(:build_and_preview_order).with(
        order_instruction: :exit,
        strategy_type: 'callspread',
        short_leg_symbol: 'SPX251219C05900',
        long_leg_symbol: 'SPX251219C06000',
        price: 0.50,
        quantiy: 1
      )

      orderable_instance.preview(orderable_instance, order_instruction: :exit)
      expect(orderable_instance.order_preview_instruction).to eq(:exit)
    end
  end

  describe '#send_order' do
    it 'sends an order and updates order details' do
      orderable_instance.send_order(orderable_instance)

      expect(orderable_instance.order_id).to eq('123456')
      expect(orderable_instance.order_status).to eq('WORKING')
      expect(orderable_instance.order).not_to be_nil
      expect(orderable_instance.order_instruction).to eq(:open)
    end

    it 'handles rejected orders' do
      allow(orderable_instance).to receive(:build_and_place_order).and_return(nil)

      orderable_instance.send_order(orderable_instance)

      expect(orderable_instance.order_status).to eq('REJECTED')
    end

    it 'accepts order_instruction parameter' do
      orderable_instance.send_order(orderable_instance, order_instruction: :exit)
      expect(orderable_instance.order_instruction).to eq(:exit)
    end
  end

  describe '#replace' do
    it 'replaces an order and updates order details' do
      # First place an order
      orderable_instance.send_order(orderable_instance)
      expect(orderable_instance.order_id).to eq('123456')

      # Replace the order
      orderable_instance.replace(orderable_instance)

      expect(orderable_instance.order_id).to eq('789012')
      expect(orderable_instance.order_status).to eq('WORKING')
      expect(orderable_instance.order.price).to eq(1.35)
    end

    it 'returns nil if no order_id exists' do
      orderable_instance.order_id = nil
      expect(orderable_instance.replace(orderable_instance)).to be_nil
    end
  end

  describe '#check_order_status' do
    it 'updates the order status and sets filled_order when order is filled' do
      # First place an order
      orderable_instance.send_order(orderable_instance)
      expect(orderable_instance.order_id).to eq('123456')
      expect(orderable_instance.order_status).to eq('WORKING')

      # Check status - should detect it's filled
      orderable_instance.check_order_status

      # Check that order status is updated
      expect(orderable_instance.order_status).to eq('FILLED')
      expect(orderable_instance.filled_order).not_to be_nil
      expect(orderable_instance.filled_order.status).to eq('FILLED')
      expect(orderable_instance.filled_order.price).to eq(1.25)
    end

    it 'clears order_id when order is rejected' do
      # Place an order
      orderable_instance.send_order(orderable_instance)
      expect(orderable_instance.order_id).to eq('123456')

      # Override the get_order stub for this test
      rejected_order = Platypi::Schwab::DataObjects::Order.build({
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

    it 'handles PENDING_ACTIVATION status' do
      orderable_instance.send_order(orderable_instance)

      pending_order = Platypi::Schwab::DataObjects::Order.build({
                                                orderId: '123456',
                                                status: 'PENDING_ACTIVATION',
                                                price: 1.25,
                                                enteredTime: test_time.iso8601
                                              })
      allow(orderable_instance).to receive(:get_order).and_return(pending_order)

      orderable_instance.check_order_status

      expect(orderable_instance.order_status).to eq('PENDING_ACTIVATION')
      expect(orderable_instance.order_id).to eq('123456')
    end

    it 'returns nil if no order_id exists' do
      orderable_instance.order_id = nil
      expect(orderable_instance.check_order_status).to be_nil
    end
  end

  describe '#cancel' do
    it 'cancels an order and clears order details' do
      # Place an order
      orderable_instance.send_order(orderable_instance)
      expect(orderable_instance.order_id).to eq('123456')

      # Cancel it
      orderable_instance.cancel

      expect(orderable_instance.order_id).to be_nil
      expect(orderable_instance.order_status).to eq('UNKNOWN')  # order_status returns 'UNKNOWN' when @order_status is nil
      expect(orderable_instance.order).to be_nil
      expect(orderable_instance.order_instruction).to be_nil
    end

    it 'returns nil if no order_id exists' do
      orderable_instance.order_id = nil
      expect(orderable_instance.cancel).to be_nil
    end
  end

  describe '#order_status' do
    it 'returns order.status when order exists' do
      orderable_instance.send_order(orderable_instance)
      expect(orderable_instance.order_status).to eq('WORKING')
    end

    it 'returns @order_status when no order exists but status is set' do
      orderable_instance.instance_variable_set(:@order_status, 'REJECTED')
      expect(orderable_instance.order_status).to eq('REJECTED')
    end

    it 'returns UNKNOWN when neither order nor @order_status exists' do
      expect(orderable_instance.order_status).to eq('UNKNOWN')
    end
  end

  describe '#filled?' do
    it 'returns true when current order status is FILLED' do
      orderable_instance.instance_variable_set(:@order_status, 'FILLED')
      expect(orderable_instance.filled?).to be true
    end

    it 'returns true when filled_order status is FILLED' do
      filled_order = Platypi::Schwab::DataObjects::Order.build({
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

    it 'returns true when order status is PENDING_ACTIVATION' do
      orderable_instance.instance_variable_set(:@order_status, 'PENDING_ACTIVATION')
      expect(orderable_instance.working?).to be true
    end

    it 'returns false when order status is not WORKING or PENDING_ACTIVATION' do
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

  describe '#accepted?' do
    it 'returns true when order status is ACCEPTED' do
      orderable_instance.instance_variable_set(:@order_status, 'ACCEPTED')
      expect(orderable_instance.accepted?).to be true
    end

    it 'returns true when filled_order status is ACCEPTED' do
      filled_order = Platypi::Schwab::DataObjects::Order.build({
                                                orderId: '123456',
                                                status: 'ACCEPTED',
                                                price: 1.25,
                                                enteredTime: DateTime.now.iso8601
                                              })
      orderable_instance.instance_variable_set(:@filled_order, filled_order)
      expect(orderable_instance.accepted?).to be true
    end

    it 'returns false when neither is ACCEPTED' do
      orderable_instance.instance_variable_set(:@order_status, 'WORKING')
      expect(orderable_instance.accepted?).to be false
    end
  end

  describe 'preview calculation methods' do
    before do
      orderable_instance.preview(orderable_instance)
    end

    describe '#preview_credit_debit' do
      it 'returns preview price multiplied by 100' do
        expect(orderable_instance.preview_credit_debit).to eq(125.0)  # 1.25 * 100
      end
    end

    describe '#preview_net_credit_debit' do
      it 'returns preview price * 100 minus fees and commission' do
        # 1.25 * 100 - 1.14 - 1.30 = 125 - 2.44 = 122.56
        expect(orderable_instance.preview_net_credit_debit).to eq(122.56)
      end
    end
  end
end
