# frozen_string_literal: true

require 'spec_helper'
require_relative '../../spx_1dte/base_order_manager'
require_relative '../../spx_1dte/data_objects'
require_relative '../../spx_1dte/constants'

RSpec.describe BaseOrderManager do
  let(:schwab_orders) { instance_double('SchwabOrders') }
  let(:mock_logger) { instance_double('Logger', info: nil, error: nil) }
  let(:order_manager) { TestOrderManager.new(schwab_orders, logger: mock_logger) }

  class TestOrderManager < BaseOrderManager
    attr_accessor :sent_orders, :order_statuses

    def initialize(*args, **kwargs)
      super
      @sent_orders = []
      @order_statuses = {}
    end

    def send_order(order_args)
      order_id = SecureRandom.uuid.delete('-')
      @sent_orders << order_args.merge(id: order_id)
      WorkingOrder.new(
        order_id,
        "schwab_#{order_id}",
        OrderStatuses::WORKING,
        nil,
        order_args,
        nil
      )
    end

    def check_order_status(order_id)
      status = @order_statuses[order_id] || OrderStatuses::WORKING
      WorkingOrder.new(
        order_id,
        "schwab_#{order_id}",
        status,
        nil,
        {},
        nil
      )
    end

    def cancel_order(order_id)
      @order_statuses[order_id] = OrderStatuses::CANCELED
      true
    end
  end

  def mock_option_leg(symbol:, mark: 1.0)
    instance_double(
      'OptionLeg',
      symbol: symbol,
      mark: mark
    )
  end

  def mock_vertical_spread(short_symbol: 'SHORT', long_symbol: 'LONG', price: 1.0, quantity: 1)
    short_leg = mock_option_leg(symbol: short_symbol, mark: 1.5)
    long_leg = mock_option_leg(symbol: long_symbol, mark: 0.5)

    instance_double(
      'VerticalSpread',
      short_leg: short_leg,
      long_leg: long_leg,
      price: price,
      quantity: quantity
    )
  end

  def mock_iron_condor(call_short: 'CALL_SHORT', call_long: 'CALL_LONG',
                       put_short: 'PUT_SHORT', put_long: 'PUT_LONG',
                       price: 2.0, quantity: 1)
    call_spread = mock_vertical_spread(
      short_symbol: call_short,
      long_symbol: call_long,
      price: 1.0,
      quantity: quantity
    )
    put_spread = mock_vertical_spread(
      short_symbol: put_short,
      long_symbol: put_long,
      price: 1.0,
      quantity: quantity
    )

    instance_double(
      'IronCondor',
      call_spread: call_spread,
      put_spread: put_spread,
      price: price,
      quantity: quantity,
      price_rounded_down_by_increment: price
    )
  end

  describe '#open_iron_condor' do
    it 'sends an order with correct arguments' do
      strategy = mock_iron_condor(
        call_short: 'SPXW_CALL_SHORT',
        call_long: 'SPXW_CALL_LONG',
        put_short: 'SPXW_PUT_SHORT',
        put_long: 'SPXW_PUT_LONG',
        price: 2.0,
        quantity: 2
      )

      result = order_manager.open_iron_condor(strategy)

      expect(result).to be_a(WorkingOrder)
      expect(result.status).to eq(OrderStatuses::WORKING)
      expect(order_manager.sent_orders.size).to eq(1)

      sent_order = order_manager.sent_orders.first
      expect(sent_order[:call_short_symbol]).to eq('SPXW_CALL_SHORT')
      expect(sent_order[:call_long_symbol]).to eq('SPXW_CALL_LONG')
      expect(sent_order[:put_short_symbol]).to eq('SPXW_PUT_SHORT')
      expect(sent_order[:put_long_symbol]).to eq('SPXW_PUT_LONG')
      expect(sent_order[:price]).to eq(2.0)
      expect(sent_order[:quantity]).to eq(2)
      expect(sent_order[:credit_debit]).to eq(:credit)
      expect(sent_order[:order_instruction]).to eq(:open)
    end

    it 'raises error when spreads have different quantities' do
      call_spread = mock_vertical_spread(quantity: 2)
      put_spread = mock_vertical_spread(quantity: 1)

      strategy = instance_double(
        'IronCondor',
        call_spread: call_spread,
        put_spread: put_spread,
        price: 2.0,
        quantity: 1,
        price_rounded_down_by_increment: 2.0
      )

      expect {
        order_manager.open_iron_condor(strategy)
      }.to raise_error(/Spreads must have equal number of contracts/)
    end
  end

  describe '#close_iron_condor' do
    it 'sends an order with correct arguments' do
      strategy = mock_iron_condor(price: 1.5, quantity: 3)

      result = order_manager.close_iron_condor(strategy)

      expect(result).to be_a(WorkingOrder)
      expect(order_manager.sent_orders.size).to eq(1)

      sent_order = order_manager.sent_orders.first
      expect(sent_order[:credit_debit]).to eq(:debit)
      expect(sent_order[:order_instruction]).to eq(:close)
      expect(sent_order[:quantity]).to eq(3)
    end
  end

  describe '#open_spread' do
    it 'sends an order with correct arguments' do
      strategy = mock_vertical_spread(
        short_symbol: 'SHORT_LEG',
        long_symbol: 'LONG_LEG',
        price: 1.25,
        quantity: 5
      )

      result = order_manager.open_spread(strategy)

      expect(result).to be_a(WorkingOrder)
      expect(order_manager.sent_orders.size).to eq(1)

      sent_order = order_manager.sent_orders.first
      expect(sent_order[:short_leg_symbol]).to eq('SHORT_LEG')
      expect(sent_order[:long_leg_symbol]).to eq('LONG_LEG')
      expect(sent_order[:price]).to eq(1.25)
      expect(sent_order[:quantity]).to eq(5)
      expect(sent_order[:credit_debit]).to eq(:credit)
      expect(sent_order[:order_instruction]).to eq(:open)
    end
  end

  describe '#close_spread' do
    it 'sends an order with correct arguments' do
      strategy = mock_vertical_spread(price: 0.75, quantity: 2)

      result = order_manager.close_spread(strategy)

      expect(result).to be_a(WorkingOrder)

      sent_order = order_manager.sent_orders.first
      expect(sent_order[:credit_debit]).to eq(:debit)
      expect(sent_order[:order_instruction]).to eq(:close)
    end
  end

  describe '#rollaway_spread' do
    it 'sends a rollaway order with correct arguments' do
      old_spread = mock_vertical_spread(
        short_symbol: 'OLD_SHORT',
        long_symbol: 'OLD_LONG',
        quantity: 1
      )
      new_spread = mock_vertical_spread(
        short_symbol: 'NEW_SHORT',
        long_symbol: 'NEW_LONG',
        quantity: 1
      )

      result = order_manager.rollaway_spread(old_spread, new_spread, price: 0.50)

      expect(result).to be_a(WorkingOrder)

      sent_order = order_manager.sent_orders.first
      expect(sent_order[:close_short_leg_symbol]).to eq('OLD_SHORT')
      expect(sent_order[:close_long_leg_symbol]).to eq('OLD_LONG')
      expect(sent_order[:open_short_leg_symbol]).to eq('NEW_SHORT')
      expect(sent_order[:open_long_leg_symbol]).to eq('NEW_LONG')
      expect(sent_order[:price]).to eq(0.50)
      expect(sent_order[:credit_debit]).to eq(:debit)
    end

    it 'raises error when price is missing' do
      old_spread = mock_vertical_spread(quantity: 1)
      new_spread = mock_vertical_spread(quantity: 1)

      expect {
        order_manager.rollaway_spread(old_spread, new_spread)
      }.to raise_error(ArgumentError, /Missing required :price/)
    end
  end

  describe '#rollup_spread' do
    it 'sends a rollup order with correct arguments' do
      old_spread = mock_vertical_spread(quantity: 1)
      new_spread = mock_vertical_spread(quantity: 1)

      result = order_manager.rollup_spread(old_spread, new_spread, price: 0.75)

      expect(result).to be_a(WorkingOrder)

      sent_order = order_manager.sent_orders.first
      expect(sent_order[:price]).to eq(0.75)
      expect(sent_order[:credit_debit]).to eq(:credit)
    end
  end

  describe '#working?' do
    it 'returns false when no orders are working' do
      expect(order_manager.working?).to be false
    end

    it 'returns true when orders are working' do
      order_manager.instance_variable_set(:@working_orders, [WorkingOrder.new('123', 'schwab_123', OrderStatuses::WORKING, nil, {}, nil)])

      expect(order_manager.working?).to be true
    end
  end

  describe '#working_orders_size' do
    it 'returns 0 when no orders are working' do
      expect(order_manager.working_orders_size).to eq(0)
    end

    it 'returns the correct count of working orders' do
      orders = [
        WorkingOrder.new('123', 'schwab_123', OrderStatuses::WORKING, nil, {}, nil),
        WorkingOrder.new('456', 'schwab_456', OrderStatuses::WORKING, nil, {}, nil)
      ]
      order_manager.instance_variable_set(:@working_orders, orders)

      expect(order_manager.working_orders_size).to eq(2)
    end
  end

  describe '#check_order_status' do
    it 'returns order status' do
      order = order_manager.send_order({ test: 'order' })

      result = order_manager.check_order_status(order.id)

      expect(result).to be_a(WorkingOrder)
      expect(result.status).to eq(OrderStatuses::WORKING)
    end
  end

  describe '#cancel_order' do
    it 'cancels an order' do
      order = order_manager.send_order({ test: 'order' })

      result = order_manager.cancel_order(order.id)

      expect(result).to be true
      expect(order_manager.check_order_status(order.id).status).to eq(OrderStatuses::CANCELED)
    end
  end
end
