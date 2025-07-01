require 'spec_helper'

RSpec.describe Platypi::Trades::OrderManager do
  let(:order_manager) { described_class.new }
  let(:mock_strategy) { double('Strategy', type: 'ironcondor', credit: 1.25, debit: 0.75, quantity: 1) }
  let(:mock_iron_condor) do
    double('IronCondor',
      type: 'ironcondor',
      credit: 1.25,
      debit: 0.75,
      quantity: 1,
      put_spread: double('PutSpread',
        short_leg: double('Option', symbol: 'SPXW240315P4900'),
        long_leg: double('Option', symbol: 'SPXW240315P4895')
      ),
      call_spread: double('CallSpread',
        short_leg: double('Option', symbol: 'SPXW240315C5100'),
        long_leg: double('Option', symbol: 'SPXW240315C5105')
      )
    )
  end

  describe '#initialize' do
    it 'initializes with clean order state' do
      expect(order_manager.order_id).to be_nil
      expect(order_manager.order_status).to eq('UNKNOWN')
      expect(order_manager.order_instruction).to be_nil
      expect(order_manager.order_price).to be_nil
      expect(order_manager.order_fees).to be_nil
      expect(order_manager.order_commission).to be_nil
      expect(order_manager.order_rejects).to eq([])
    end
  end

  describe '#order_status' do
    context 'when order object exists' do
      let(:mock_order) { double('Order', status: 'WORKING') }

      before { order_manager.instance_variable_set(:@order, mock_order) }

      it 'returns the order object status' do
        expect(order_manager.order_status).to eq('WORKING')
      end
    end

    context 'when only @order_status is set' do
      before { order_manager.instance_variable_set(:@order_status, 'FILLED') }

      it 'returns the @order_status value' do
        expect(order_manager.order_status).to eq('FILLED')
      end
    end

    context 'when neither exists' do
      it 'returns UNKNOWN' do
        expect(order_manager.order_status).to eq('UNKNOWN')
      end
    end
  end

  describe '#filled?' do
    it 'returns true when order_status is FILLED' do
      order_manager.instance_variable_set(:@order_status, 'FILLED')
      expect(order_manager).to be_filled
    end

    it 'returns true when filled_order status is FILLED' do
      filled_order = double('Order', status: 'FILLED')
      order_manager.instance_variable_set(:@filled_order, filled_order)
      expect(order_manager).to be_filled
    end

    it 'returns false when neither condition is met' do
      expect(order_manager).not_to be_filled
    end
  end

  describe '#working?' do
    it 'returns true for WORKING status' do
      order_manager.instance_variable_set(:@order_status, 'WORKING')
      expect(order_manager).to be_working
    end

    it 'returns true for PENDING_ACTIVATION status' do
      order_manager.instance_variable_set(:@order_status, 'PENDING_ACTIVATION')
      expect(order_manager).to be_working
    end

    it 'returns false for other statuses' do
      order_manager.instance_variable_set(:@order_status, 'FILLED')
      expect(order_manager).not_to be_working
    end
  end

  describe '#failed?' do
    %w[REJECTED EXPIRED CANCELED].each do |status|
      it "returns true for #{status} status" do
        order_manager.instance_variable_set(:@order_status, status)
        expect(order_manager).to be_failed
      end
    end

    it 'returns false for successful statuses' do
      order_manager.instance_variable_set(:@order_status, 'FILLED')
      expect(order_manager).not_to be_failed
    end
  end

  describe '#accepted?' do
    it 'returns true when order_status is ACCEPTED' do
      order_manager.instance_variable_set(:@order_status, 'ACCEPTED')
      expect(order_manager).to be_accepted
    end

    it 'returns true when filled_order status is ACCEPTED' do
      filled_order = double('Order', status: 'ACCEPTED')
      order_manager.instance_variable_set(:@filled_order, filled_order)
      expect(order_manager).to be_accepted
    end

    it 'returns false when neither condition is met' do
      expect(order_manager).not_to be_accepted
    end
  end

  describe '#send_preview_order' do
    let(:mock_order_preview) do
      double('OrderPreview',
        order_id: 'preview-123',
        price: 1.25,
        fees: 0.50,
        commission: 0.65,
        status: 'ACCEPTED',
        accepted?: true
      )
    end

    before do
      allow(order_manager).to receive(:build_and_preview_order).and_return(mock_order_preview)
      allow(order_manager).to receive(:extract_strategy_kwargs).and_return({})
    end

    it 'builds and sends a preview order' do
      expect(order_manager).to receive(:build_and_preview_order).with(
        hash_including(order_instruction: :open)
      ).and_return(mock_order_preview)

      result = order_manager.send_preview_order(mock_strategy, order_instruction: :open)

      expect(result).to eq(mock_order_preview)
      expect(order_manager.order_id).to eq('preview-123')
      expect(order_manager.order_instruction).to eq(:open)
      expect(order_manager.order_price).to eq(1.25)
      expect(order_manager.order_fees).to eq(0.50)
      expect(order_manager.order_commission).to eq(0.65)
      expect(order_manager.order_status).to eq('ACCEPTED')
      expect(order_manager.order_rejects).to eq([])
    end

    context 'when order is rejected' do
      let(:mock_rejected_preview) do
        double('OrderPreview',
          order_id: 'preview-456',
          price: 1.25,
          fees: 0.50,
          commission: 0.65,
          status: 'REJECTED',
          accepted?: false,
          order_validation_result: double('ValidationResult',
            rejects: [
              double('Reject', activity_message: 'Insufficient buying power')
            ]
          )
        )
      end

      before do
        allow(order_manager).to receive(:build_and_preview_order).and_return(mock_rejected_preview)
      end

      it 'captures rejection reasons' do
        order_manager.send_preview_order(mock_strategy)

        expect(order_manager.order_rejects).to eq(['Insufficient buying power'])
      end
    end
  end

  describe '#send_order' do
    let(:mock_order) do
      double('Order',
        order_id: 'live-789',
        status: 'WORKING'
      )
    end

    before do
      allow(order_manager).to receive(:build_and_place_order).and_return(mock_order)
      allow(order_manager).to receive(:extract_strategy_kwargs).and_return({})
    end

    it 'builds and places a live order' do
      expect(order_manager).to receive(:build_and_place_order).with(
        hash_including(order_instruction: :open)
      ).and_return(mock_order)

      result = order_manager.send_order(mock_strategy, order_instruction: :open)

      expect(result).to eq(mock_order)
      expect(order_manager.order_id).to eq('live-789')
      expect(order_manager.order_status).to eq('WORKING')
      expect(order_manager.order_instruction).to eq(:open)
    end

    context 'when order fails' do
      before do
        allow(order_manager).to receive(:build_and_place_order).and_return(nil)
      end

      it 'sets status to REJECTED' do
        order_manager.send_order(mock_strategy)

        expect(order_manager.order_status).to eq('REJECTED')
      end
    end
  end

  describe '#check_order_status' do
    context 'when order_id exists' do
      let(:mock_order) { double('Order', status: 'FILLED', order_id: 'test-123') }

      before do
        order_manager.instance_variable_set(:@order_id, 'test-123')
        allow(order_manager).to receive(:get_order).with('test-123').and_return(mock_order)
      end

      it 'fetches and updates order status' do
        result = order_manager.check_order_status

        expect(result).to eq(mock_order)
        expect(order_manager.order_status).to eq('FILLED')
        expect(order_manager.filled_order).to eq(mock_order)
      end
    end

    context 'when no order_id exists' do
      it 'returns nil' do
        expect(order_manager.check_order_status).to be_nil
      end
    end
  end

  describe '#stop_order' do
    context 'when order_id exists' do
      before do
        order_manager.instance_variable_set(:@order_id, 'test-123')
        order_manager.instance_variable_set(:@order_status, 'WORKING')
      end

      it 'cancels the order successfully' do
        allow(order_manager).to receive(:cancel_order).with('test-123').and_return(true)

        result = order_manager.stop_order

        expect(result).to be(true)
        expect(order_manager.order_id).to be_nil
        expect(order_manager.order_status).to eq('UNKNOWN')
      end

      it 'does not reset state when cancellation fails' do
        allow(order_manager).to receive(:cancel_order).with('test-123').and_return(false)

        result = order_manager.stop_order

        expect(result).to be(false)
        expect(order_manager.order_id).to eq('test-123')
        expect(order_manager.order_status).to eq('WORKING')
      end
    end

    context 'when no order_id exists' do
      it 'returns nil' do
        expect(order_manager.stop_order).to be_nil
      end
    end
  end

  describe '#to_h' do
    before do
      order_manager.instance_variable_set(:@order_id, 'test-123')
      order_manager.instance_variable_set(:@order_instruction, :open)
      order_manager.instance_variable_set(:@order_status, 'FILLED')
      order_manager.instance_variable_set(:@order_price, 1.25)
      order_manager.instance_variable_set(:@order_fees, 0.50)
      order_manager.instance_variable_set(:@order_commission, 0.65)
      order_manager.instance_variable_set(:@order_rejects, ['test reject'])
    end

    it 'returns a hash representation of the order state' do
      result = order_manager.to_h

      expect(result).to eq({
        order_id: 'test-123',
        order_instruction: :open,
        order_status: 'FILLED',
        order_price: 1.25,
        order_fees: 0.50,
        order_commission: 0.65,
        order_datetime: nil,
        order_rejects: ['test reject']
      })
    end
  end

  describe '#restore_from_hash' do
    let(:order_data) do
      {
        order_id: 'restored-123',
        order_status: 'FILLED',
        order_instruction: 'open',
        order_price: 2.50,
        order_fees: 1.00,
        order_commission: 1.30,
        order_rejects: ['test reject']
      }
    end

    it 'restores order state from hash data' do
      order_manager.restore_from_hash(order_data)

      expect(order_manager.order_id).to eq('restored-123')
      expect(order_manager.order_status).to eq('FILLED')
      expect(order_manager.order_instruction).to eq(:open)
      expect(order_manager.order_price).to eq(2.50)
      expect(order_manager.order_fees).to eq(1.00)
      expect(order_manager.order_commission).to eq(1.30)
      expect(order_manager.order_rejects).to eq(['test reject'])
    end

    it 'handles missing order_rejects' do
      order_data.delete(:order_rejects)
      order_manager.restore_from_hash(order_data)

      expect(order_manager.order_rejects).to eq([])
    end
  end

  describe '#extract_strategy_kwargs' do
    context 'with iron condor strategy' do
      it 'extracts correct parameters for opening' do
        result = order_manager.send(:extract_strategy_kwargs, mock_iron_condor, order_instruction: :open)

        expect(result).to eq({
          strategy_type: 'ironcondor',
          put_short_symbol: 'SPXW240315P4900',
          put_long_symbol: 'SPXW240315P4895',
          call_short_symbol: 'SPXW240315C5100',
          call_long_symbol: 'SPXW240315C5105',
          price: 1.25,
          quantity: 1
        })
      end

      it 'extracts correct parameters for exiting' do
        result = order_manager.send(:extract_strategy_kwargs, mock_iron_condor, order_instruction: :exit)

        expect(result).to eq({
          strategy_type: 'ironcondor',
          put_short_symbol: 'SPXW240315P4900',
          put_long_symbol: 'SPXW240315P4895',
          call_short_symbol: 'SPXW240315C5100',
          call_long_symbol: 'SPXW240315C5105',
          price: 0.75,
          quantity: 1
        })
      end
    end

    context 'with call spread strategy' do
      let(:mock_call_spread) do
        double('CallSpread',
          type: 'callspread',
          credit: 0.85,
          debit: 0.45,
          quantity: 2,
          short_leg: double('Option', symbol: 'SPXW240315C5100'),
          long_leg: double('Option', symbol: 'SPXW240315C5105')
        )
      end

      it 'extracts correct parameters' do
        result = order_manager.send(:extract_strategy_kwargs, mock_call_spread, order_instruction: :open)

        expect(result).to eq({
          strategy_type: 'callspread',
          short_leg_symbol: 'SPXW240315C5100',
          long_leg_symbol: 'SPXW240315C5105',
          price: 0.85,
          quantiy: 2  # Note: This appears to be a typo in the original code
        })
      end
    end

    context 'with unsupported strategy type' do
      let(:mock_unsupported) { double('Strategy', type: 'butterfly') }

      it 'raises an error' do
        expect {
          order_manager.send(:extract_strategy_kwargs, mock_unsupported)
        }.to raise_error("Unsupported strategy type: butterfly")
      end
    end
  end

  describe '#strategy_price' do
    it 'returns credit for open instruction' do
      result = order_manager.send(:strategy_price, mock_strategy, :open)
      expect(result).to eq(1.25)
    end

    it 'returns absolute debit for exit instruction' do
      result = order_manager.send(:strategy_price, mock_strategy, :exit)
      expect(result).to eq(0.75)
    end

    it 'raises error for unsupported instruction' do
      expect {
        order_manager.send(:strategy_price, mock_strategy, :adjust)
      }.to raise_error("Unsupported order instruction: adjust")
    end
  end

  describe '#preview_credit_debit' do
    before { order_manager.instance_variable_set(:@order_price, 1.25) }

    it 'calculates credit/debit in cents' do
      expect(order_manager.preview_credit_debit).to eq(125.0)
    end
  end

  describe '#preview_net_credit_debit' do
    before do
      order_manager.instance_variable_set(:@order_price, 1.25)
      order_manager.instance_variable_set(:@order_fees, 0.50)
      order_manager.instance_variable_set(:@order_commission, 0.65)
    end

    it 'calculates net credit/debit after fees and commission' do
      expect(order_manager.preview_net_credit_debit).to eq(123.85)
    end
  end
end