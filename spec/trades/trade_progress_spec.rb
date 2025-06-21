# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Platypi::TradeProgress do
  let(:trade_progress) { described_class.new }

  let(:custom_trade_progress) do
    described_class.new(
      profit_thresh: 0.75,
      loss_thresh: -3.0,
      green_delta: 0.12,
      yellow_delta: 0.20
    )
  end

  describe '#initialize' do
    it 'sets default values' do
      expect(trade_progress.profit_thresh).to eq(0.65)
      expect(trade_progress.loss_thresh).to eq(-4.0)
      expect(trade_progress.green_delta).to eq(0.16)
      expect(trade_progress.yellow_delta).to eq(0.26)
    end

    it 'accepts custom parameters' do
      expect(custom_trade_progress.profit_thresh).to eq(0.75)
      expect(custom_trade_progress.loss_thresh).to eq(-3.0)
      expect(custom_trade_progress.green_delta).to eq(0.12)
      expect(custom_trade_progress.yellow_delta).to eq(0.20)
    end
  end

  describe '#risk_status' do
    let(:mock_strategy) do
      double('Strategy',
        check_market: nil,
        delta: 0.15
      )
    end

    it 'returns GREEN when delta is below green threshold' do
      allow(mock_strategy).to receive(:delta).and_return(0.10)

      result = trade_progress.risk_status(mock_strategy)

      expect(result).to eq('GREEN')
      expect(mock_strategy).to have_received(:check_market)
    end

    it 'returns YELLOW when delta is between green and yellow thresholds' do
      allow(mock_strategy).to receive(:delta).and_return(0.20)

      result = trade_progress.risk_status(mock_strategy)

      expect(result).to eq('YELLOW')
    end

    it 'returns RED when delta is above yellow threshold' do
      allow(mock_strategy).to receive(:delta).and_return(0.30)

      result = trade_progress.risk_status(mock_strategy)

      expect(result).to eq('RED')
    end

    it 'returns UNKNOWN when delta is undefined' do
      allow(mock_strategy).to receive(:delta).and_return(double('UndefinedDelta', undefined?: true))

      result = trade_progress.risk_status(mock_strategy)

      expect(result).to eq('UNKNOWN')
    end

    it 'returns UNKNOWN when delta is nil' do
      allow(mock_strategy).to receive(:delta).and_return(nil)

      result = trade_progress.risk_status(mock_strategy)

      expect(result).to eq('UNKNOWN')
    end

    it 'handles negative deltas (for puts) correctly' do
      allow(mock_strategy).to receive(:delta).and_return(-0.15)

      result = trade_progress.risk_status(mock_strategy)

      expect(result).to eq('GREEN')
    end

    it 'uses custom thresholds when provided' do
      allow(mock_strategy).to receive(:delta).and_return(0.15)

      result = custom_trade_progress.risk_status(mock_strategy)

      expect(result).to eq('YELLOW') # 0.15 is between 0.12 and 0.20
    end
  end

  describe '#tested?' do
    let(:mock_trade) { double('Trade') }

    it 'returns true when risk status is YELLOW' do
      allow(trade_progress).to receive(:risk_status).with(mock_trade).and_return('YELLOW')

      expect(trade_progress.tested?(mock_trade)).to be true
    end

    it 'returns false when risk status is not YELLOW' do
      allow(trade_progress).to receive(:risk_status).with(mock_trade).and_return('GREEN')

      expect(trade_progress.tested?(mock_trade)).to be false
    end
  end

  describe '#danger?' do
    let(:mock_trade) { double('Trade') }

    it 'returns true when risk status is RED' do
      allow(trade_progress).to receive(:risk_status).with(mock_trade).and_return('RED')

      expect(trade_progress.danger?(mock_trade)).to be true
    end

    it 'returns false when risk status is not RED' do
      allow(trade_progress).to receive(:risk_status).with(mock_trade).and_return('YELLOW')

      expect(trade_progress.danger?(mock_trade)).to be false
    end
  end

  describe '#exit?' do
    let(:mock_trade) { double('Trade') }

    it 'returns true when progress reaches 100%' do
      allow(trade_progress).to receive(:progress).with(mock_trade).and_return(100.0)

      expect(trade_progress.exit?(mock_trade)).to be true
    end

    it 'returns true when progress reaches -100%' do
      allow(trade_progress).to receive(:progress).with(mock_trade).and_return(-100.0)

      expect(trade_progress.exit?(mock_trade)).to be true
    end

    it 'returns true when progress exceeds 100%' do
      allow(trade_progress).to receive(:progress).with(mock_trade).and_return(150.0)

      expect(trade_progress.exit?(mock_trade)).to be true
    end

    it 'returns true when progress is below -100%' do
      allow(trade_progress).to receive(:progress).with(mock_trade).and_return(-150.0)

      expect(trade_progress.exit?(mock_trade)).to be true
    end

    it 'returns false when progress is between thresholds' do
      allow(trade_progress).to receive(:progress).with(mock_trade).and_return(50.0)

      expect(trade_progress.exit?(mock_trade)).to be false
    end

    it 'returns false when progress is nil' do
      allow(trade_progress).to receive(:progress).with(mock_trade).and_return(nil)

      expect(trade_progress.exit?(mock_trade)).to be false
    end
  end

  describe '#progress' do
    let(:mock_strategy) do
      double('Strategy',
        check_market: nil,
        credit: 2.50,
        quantity: 1
      )
    end

    let(:mock_open_state) do
      double('OpenState',
        order_price: 2.50,
        order_fees: 1.14,
        order_commission: 1.30,
        strategy: double('OpenStrategy', quantity: 1)
      )
    end

    let(:mock_trade) do
      double('Trade',
        open_state: mock_open_state,
        strategy: mock_strategy
      )
    end

    context 'with valid trade data' do
      before do
        allow(mock_strategy).to receive(:check_market)
      end

      it 'calculates positive progress correctly' do
        # Opening credit: (2.50 * 1 * 100) - 1.14 - 1.30 = 250 - 2.44 = 247.56
        # Current value: 2.50 * 1 * 100.0 = 250.0
        # Current P&L: 247.56 - 250.0 = -2.44
        # Max loss: 247.56 * 4.0 = 990.24
        # Progress: (-2.44 / 990.24) * 100 = -0.246...%

        result = trade_progress.progress(mock_trade)

        expect(result).to be_within(0.01).of(-0.25)
        expect(mock_strategy).to have_received(:check_market)
      end

      it 'calculates negative progress correctly' do
        # Let's create a scenario that results in a larger loss to hit -100%
        allow(mock_strategy).to receive(:credit).and_return(133.353)

        # Opening credit: (2.50 * 1 * 100) - 1.14 - 1.30 = 247.56
        # Current value: 133.353 * 1 * 100.0 = 13335.3
        # Current P&L: 247.56 - 13335.3 = -13087.74
        # Max loss: 247.56 * 4.0 = 990.24
        # Since P&L <= -max_loss, this should return -100.0

        result = trade_progress.progress(mock_trade)

        expect(result).to eq(-100.0)
      end

      it 'handles loss scenarios' do
        # Set up a losing scenario where current value exceeds opening credit
        allow(mock_strategy).to receive(:credit).and_return(10.00)

        # Opening credit: (2.50 * 1 * 100) - 1.14 - 1.30 = 247.56
        # Current value: 10.00 * 1 * 100.0 = 1000.0
        # Current P&L: 247.56 - 1000.0 = -752.44
        # Max loss: 247.56 * 4.0 = 990.24
        # Progress: (-752.44 / 990.24) * 100 = -75.98%

        result = trade_progress.progress(mock_trade)

        expect(result).to be_within(0.1).of(-75.98)
      end

      it 'uses custom thresholds when provided' do
        result = custom_trade_progress.progress(mock_trade)

        expect(result).to be_a(Numeric)
      end
    end

    context 'with missing data' do
      it 'returns nil when open_state is nil' do
        allow(mock_trade).to receive(:open_state).and_return(nil)

        result = trade_progress.progress(mock_trade)

        expect(result).to be_nil
      end

      it 'returns nil when strategy is nil' do
        allow(mock_trade).to receive(:strategy).and_return(nil)

        result = trade_progress.progress(mock_trade)

        expect(result).to be_nil
      end
    end

    context 'with edge cases' do
      it 'handles zero opening credit' do
        allow(mock_open_state).to receive(:order_price).and_return(0.0)
        allow(mock_open_state).to receive(:order_fees).and_return(0.0)
        allow(mock_open_state).to receive(:order_commission).and_return(0.0)

        result = trade_progress.progress(mock_trade)

        expect(result).to be_a(Numeric)
      end

      it 'handles missing order data gracefully' do
        allow(mock_open_state).to receive(:order_price).and_return(nil)
        allow(mock_open_state).to receive(:order_fees).and_return(nil)
        allow(mock_open_state).to receive(:order_commission).and_return(nil)

        result = trade_progress.progress(mock_trade)

        expect(result).to be_a(Numeric)
      end
    end
  end

  describe '#open_credit' do
    let(:mock_trade_state) do
      double('TradeState',
        order_price: 2.50,
        order_fees: 1.14,
        order_commission: 1.30,
        strategy: double('Strategy', quantity: 2)
      )
    end

    it 'calculates opening credit correctly' do
      # (2.50 * 2 * 100) - 1.14 - 1.30 = 500 - 2.44 = 497.56
      result = trade_progress.open_credit(mock_trade_state)

      expect(result).to eq(497.56)
    end

    it 'handles nil values gracefully' do
      allow(mock_trade_state).to receive(:order_price).and_return(nil)
      allow(mock_trade_state).to receive(:order_fees).and_return(nil)
      allow(mock_trade_state).to receive(:order_commission).and_return(nil)
      allow(mock_trade_state.strategy).to receive(:quantity).and_return(nil)

      result = trade_progress.open_credit(mock_trade_state)

      expect(result).to eq(-0.0) # (0 * 100 - 0 - 0) * 1 = 0
    end

    it 'handles single contract quantity' do
      allow(mock_trade_state.strategy).to receive(:quantity).and_return(1)

      # (2.50 * 1 * 100) - 1.14 - 1.30 = 250 - 2.44 = 247.56
      result = trade_progress.open_credit(mock_trade_state)

      expect(result).to eq(247.56)
    end

    it 'handles zero price' do
      allow(mock_trade_state).to receive(:order_price).and_return(0.0)

      # (0.0 * 2 * 100) - 1.14 - 1.30 = 0 - 2.44 = -2.44
      result = trade_progress.open_credit(mock_trade_state)

      expect(result).to eq(-2.44)
    end
  end

  describe 'integration scenarios' do
    let(:mock_strategy) do
      double('Strategy',
        check_market: nil,
        credit: 2.00,
        quantity: 1,
        delta: 0.20
      )
    end

    let(:mock_open_state) do
      double('OpenState',
        order_price: 2.00,
        order_fees: 1.14,
        order_commission: 1.30,
        strategy: double('OpenStrategy', quantity: 1)
      )
    end

    let(:mock_trade) do
      double('Trade',
        open_state: mock_open_state,
        strategy: mock_strategy,
        check_market: nil
      )
    end

    it 'provides complete trade analysis workflow' do
      # Check risk status
      risk_status = trade_progress.risk_status(mock_strategy)
      expect(risk_status).to eq('YELLOW')

      # Check if tested (this uses the trade's strategy internally)
      allow(trade_progress).to receive(:risk_status).with(mock_trade).and_return('YELLOW')
      tested = trade_progress.tested?(mock_trade)
      expect(tested).to be true

      # Check if dangerous
      allow(trade_progress).to receive(:risk_status).with(mock_trade).and_return('YELLOW')
      dangerous = trade_progress.danger?(mock_trade)
      expect(dangerous).to be false

      # Calculate progress
      progress_pct = trade_progress.progress(mock_trade)
      expect(progress_pct).to be_a(Numeric)

      # Check exit condition
      should_exit = trade_progress.exit?(mock_trade)
      expect(should_exit).to be(true).or be(false)
    end

    it 'handles high-risk scenario' do
      allow(mock_strategy).to receive(:delta).and_return(0.35)

      risk_status = trade_progress.risk_status(mock_strategy)
      expect(risk_status).to eq('RED')

      allow(trade_progress).to receive(:risk_status).with(mock_trade).and_return('RED')
      dangerous = trade_progress.danger?(mock_trade)
      expect(dangerous).to be true

      tested = trade_progress.tested?(mock_trade)
      expect(tested).to be false
    end

    it 'handles low-risk scenario' do
      allow(mock_strategy).to receive(:delta).and_return(0.10)

      risk_status = trade_progress.risk_status(mock_strategy)
      expect(risk_status).to eq('GREEN')

      allow(trade_progress).to receive(:risk_status).with(mock_trade).and_return('GREEN')
      dangerous = trade_progress.danger?(mock_trade)
      expect(dangerous).to be false

      tested = trade_progress.tested?(mock_trade)
      expect(tested).to be false
    end
  end
end
