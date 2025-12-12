require 'spec_helper'
require_relative '../../spx_1dte/order_manager'
require_relative '../../spx_1dte/data_objects'
require_relative '../../spx_1dte/constants'

RSpec.describe OrderManager do
  let(:mock_schwab_orders) { double('SchwabOrders') }
  let(:mock_logger) { double('Logger', info: nil, error: nil, warn: nil) }
  let(:order_manager) { described_class.new(mock_schwab_orders, fill_wait_time: 20, logger: mock_logger) }

  describe '#send_order' do
    let(:order_args) do
      {
        order_instruction: :open,
        price: 1.50,
        quantity: 1,
        strategy_type: 'VERTICAL'
      }
    end

    context 'when preview is rejected' do
      let(:preview_result) { double('PreviewResult', status: OrderStatuses::REJECTED, order_id: 'preview-123') }

      it 'returns a rejected WorkingOrder without placing the order' do
        expect(mock_schwab_orders).to receive(:preview_order).and_return(preview_result)
        expect(mock_schwab_orders).not_to receive(:place_order)

        result = order_manager.send_order(order_args)

        expect(result.status).to eq(OrderStatuses::REJECTED)
        expect(result.schwab_id).to eq('preview-123')
        expect(order_manager.working_orders_size).to eq(0)
      end
    end

    context 'when preview is accepted and order is placed successfully' do
      let(:preview_result) { double('PreviewResult', status: OrderStatuses::ACCEPTED, order_id: 'preview-123') }
      let(:placed_order) { double('PlacedOrder', status: OrderStatuses::WORKING, order_id: 'order-456') }

      it 'places the order and returns a working WorkingOrder' do
        expect(mock_schwab_orders).to receive(:preview_order).and_return(preview_result)
        expect(mock_schwab_orders).to receive(:place_order).and_return(placed_order)

        result = order_manager.send_order(order_args)

        expect(result.status).to eq(OrderStatuses::WORKING)
        expect(result.schwab_id).to eq('order-456')
        expect(order_manager.working_orders_size).to eq(1)
      end
    end

    context 'when order placement fails' do
      let(:preview_result) { double('PreviewResult', status: OrderStatuses::ACCEPTED, order_id: 'preview-123') }

      it 'returns a rejected WorkingOrder when placed_order is nil' do
        expect(mock_schwab_orders).to receive(:preview_order).and_return(preview_result)
        expect(mock_schwab_orders).to receive(:place_order).and_return(nil)

        result = order_manager.send_order(order_args)

        expect(result.status).to eq(OrderStatuses::REJECTED)
        expect(order_manager.working_orders_size).to eq(0)
      end
    end
  end

  describe '#check_order_status' do
    let(:order_args) { { order_instruction: :open, schwab_order_id: 'order-123' } }
    let(:preview_result) { double('PreviewResult', status: OrderStatuses::ACCEPTED, order_id: 'preview-123') }
    let(:placed_order) { double('PlacedOrder', status: OrderStatuses::WORKING, order_id: 'order-123') }

    before do
      allow(mock_schwab_orders).to receive(:preview_order).and_return(preview_result)
      allow(mock_schwab_orders).to receive(:place_order).and_return(placed_order)
      order_manager.send_order(order_args)
    end

    context 'when order is filled' do
      let(:filled_order) do
        double('FilledOrder',
          status: 'FILLED',
          price: 1.50,
          quantity: 1,
          order_activity_collection: [
            double('Activity', execution_legs: [
              double('Leg', fees: 0.50, commissions: 0.00)
            ])
          ]
        )
      end

      it 'removes order from working orders and marks as filled' do
        expect(mock_schwab_orders).to receive(:get_order).with('order-123').and_return(filled_order)

        order_id = order_manager.instance_variable_get(:@working_orders).first.id
        result = order_manager.check_order_status(order_id)

        expect(result.status).to eq(OrderStatuses::FILLED)
        expect(order_manager.working_orders_size).to eq(0)
      end
    end

    context 'when order has been working too long' do
      let(:working_order) { double('WorkingOrder', status: 'WORKING') }

      it 'cancels the order' do
        # Set sent_time to be old enough to trigger cancellation
        working_order_obj = order_manager.instance_variable_get(:@working_orders).first
        working_order_obj.instance_variable_set(:@sent_time, Time.now - 30)

        expect(mock_schwab_orders).to receive(:get_order).and_return(working_order)
        expect(mock_schwab_orders).to receive(:cancel_order).with('order-123').and_return(true)

        order_manager.check_order_status(working_order_obj.id)

        expect(order_manager.working_orders_size).to eq(0)
      end
    end
  end

  describe '#cancel_order' do
    let(:order_args) { { order_instruction: :open, schwab_order_id: 'order-123' } }
    let(:preview_result) { double('PreviewResult', status: OrderStatuses::ACCEPTED, order_id: 'preview-123') }
    let(:placed_order) { double('PlacedOrder', status: OrderStatuses::WORKING, order_id: 'order-123') }

    before do
      allow(mock_schwab_orders).to receive(:preview_order).and_return(preview_result)
      allow(mock_schwab_orders).to receive(:place_order).and_return(placed_order)
      order_manager.send_order(order_args)
    end

    it 'calls Schwab API to cancel and removes from working orders' do
      order_id = order_manager.instance_variable_get(:@working_orders).first.id

      expect(mock_schwab_orders).to receive(:cancel_order).with('order-123').and_return(true)

      result = order_manager.cancel_order(order_id)

      expect(result.status).to eq(OrderStatuses::CANCELED)
      expect(order_manager.working_orders_size).to eq(0)
    end

    it 'returns nil when cancellation fails' do
      order_id = order_manager.instance_variable_get(:@working_orders).first.id

      expect(mock_schwab_orders).to receive(:cancel_order).with('order-123').and_return(false)

      result = order_manager.cancel_order(order_id)

      expect(result).to be_nil
      expect(order_manager.working_orders_size).to eq(1)
    end
  end
end
