require 'spec_helper'
require_relative '../../spx_1dte/paper_order_manager'
require_relative '../../spx_1dte/data_objects'
require_relative '../../spx_1dte/constants'

RSpec.describe PaperOrderManager do
  let(:mock_schwab_orders) { double('SchwabOrders') }
  let(:mock_logger) { double('Logger', info: nil, error: nil, warn: nil) }
  let(:order_manager) { described_class.new(mock_schwab_orders, fill_wait_time: 20, logger: mock_logger) }

  describe '#send_order' do
    let(:order_args) do
      {
        order_instruction: :open,
        price: 1.50,
        quantity: 1,
        strategy_type: SchwabRb::Order::ComplexOrderStrategyTypes::VERTICAL
      }
    end

    context 'when preview is accepted for open order' do
      let(:preview_result) do
        double('PreviewResult',
          status: OrderStatuses::ACCEPTED,
          order_id: 'preview-123',
          price: 1.50,
          quantity: 1,
          fees: 0.50,
          commission: 0.00
        )
      end

      it 'creates a working order with simulated fill time' do
        expect(mock_schwab_orders).to receive(:preview_order).and_return(preview_result)

        result = order_manager.send_order(order_args)

        expect(result.status).to eq(OrderStatuses::WORKING)
        expect(result.schwab_id).to eq('preview-123')
        expect(result.fill_time).to be > Time.now
        expect(order_manager.working_orders_size).to eq(1)
      end
    end

    context 'when preview is rejected for open order' do
      let(:preview_result) do
        double('PreviewResult',
          status: OrderStatuses::REJECTED,
          order_id: 'preview-123',
          order_validation_result: double('ValidationResult',
            rejects: [
              double('Reject', activity_message: '"Insufficient buying power"')
            ]
          )
        )
      end

      it 'returns a rejected WorkingOrder without adding to working orders' do
        expect(mock_schwab_orders).to receive(:preview_order).and_return(preview_result)

        result = order_manager.send_order(order_args)

        expect(result.status).to eq(OrderStatuses::REJECTED)
        expect(order_manager.working_orders_size).to eq(0)
      end
    end

    context 'when preview is rejected but order_instruction is close' do
      let(:close_order_args) { order_args.merge(order_instruction: :close) }
      let(:preview_result) do
        double('PreviewResult',
          status: OrderStatuses::REJECTED,
          order_id: 'preview-123',
          price: 1.50,
          quantity: 1,
          fees: 0.50,
          commission: 0.00
        )
      end

      it 'accepts the order anyway (paper trading workaround)' do
        expect(mock_schwab_orders).to receive(:preview_order).and_return(preview_result)

        result = order_manager.send_order(close_order_args)

        expect(result.status).to eq(OrderStatuses::WORKING)
        expect(order_manager.working_orders_size).to eq(1)
      end
    end

    context 'when order is a vertical roll' do
      let(:roll_order_args) do
        order_args.merge(strategy_type: SchwabRb::Order::ComplexOrderStrategyTypes::VERTICAL_ROLL)
      end
      let(:preview_result) do
        double('PreviewResult',
          status: OrderStatuses::REJECTED,
          order_id: 'preview-123',
          price: 1.50,
          quantity: 1,
          fees: 0.50,
          commission: 0.00
        )
      end

      it 'accepts the order anyway (paper trading workaround)' do
        expect(mock_schwab_orders).to receive(:preview_order).and_return(preview_result)

        result = order_manager.send_order(roll_order_args)

        expect(result.status).to eq(OrderStatuses::WORKING)
        expect(order_manager.working_orders_size).to eq(1)
      end
    end
  end

  describe '#check_order_status' do
    let(:order_args) { { order_instruction: :open, schwab_order_id: 'order-123' } }
    let(:preview_result) do
      double('PreviewResult',
        status: OrderStatuses::ACCEPTED,
        order_id: 'order-123',
        price: 1.50,
        quantity: 1,
        fees: 0.50,
        commission: 0.00
      )
    end

    before do
      allow(mock_schwab_orders).to receive(:preview_order).and_return(preview_result)
    end

    context 'when fill time has been reached' do
      it 'marks order as filled and removes from working orders' do
        # Create order with fill time in the past
        allow(order_manager).to receive(:order_fill_delay).and_return(Time.now - 1)
        order_manager.send_order(order_args)

        order_id = order_manager.instance_variable_get(:@working_orders).first.id
        result = order_manager.check_order_status(order_id)

        expect(result.status).to eq(OrderStatuses::FILLED)
        expect(order_manager.working_orders_size).to eq(0)
      end
    end

    context 'when order has been working too long' do
      it 'cancels the order' do
        # Create order with old sent_time but future fill_time
        allow(order_manager).to receive(:order_fill_delay).and_return(Time.now + 100)
        order_manager.send_order(order_args)

        working_order = order_manager.instance_variable_get(:@working_orders).first
        working_order.instance_variable_set(:@sent_time, Time.now - 30)

        result = order_manager.check_order_status(working_order.id)

        expect(result.status).to eq(OrderStatuses::CANCELED)
        expect(order_manager.working_orders_size).to eq(0)
      end
    end

    context 'when order is still working normally' do
      it 'returns the order unchanged' do
        # Create order with future fill time
        allow(order_manager).to receive(:order_fill_delay).and_return(Time.now + 10)
        order_manager.send_order(order_args)

        order_id = order_manager.instance_variable_get(:@working_orders).first.id
        result = order_manager.check_order_status(order_id)

        expect(result.status).to eq(OrderStatuses::WORKING)
        expect(order_manager.working_orders_size).to eq(1)
      end
    end
  end

  describe '#cancel_order' do
    let(:order_args) { { order_instruction: :open, schwab_order_id: 'order-123' } }
    let(:preview_result) do
      double('PreviewResult',
        status: OrderStatuses::ACCEPTED,
        order_id: 'order-123',
        price: 1.50,
        quantity: 1,
        fees: 0.50,
        commission: 0.00
      )
    end

    before do
      allow(mock_schwab_orders).to receive(:preview_order).and_return(preview_result)
      order_manager.send_order(order_args)
    end

    it 'immediately removes order from working orders without API call' do
      order_id = order_manager.instance_variable_get(:@working_orders).first.id

      result = order_manager.cancel_order(order_id)

      expect(result.status).to eq(OrderStatuses::CANCELED)
      expect(order_manager.working_orders_size).to eq(0)
    end
  end

  describe '#order_fill_delay' do
    it 'returns a time between now and 30 seconds in the future' do
      result = order_manager.order_fill_delay

      expect(result).to be > Time.now
      expect(result).to be <= Time.now + 30
    end
  end
end
