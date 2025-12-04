# frozen_string_literal: true

require 'spec_helper'
require_relative '../../spx_1dte/trade_state_machine'
require_relative '../../spx_1dte/iron_condor_trade'
require_relative '../../spx_1dte/data_objects'

RSpec.describe TradeStateMachine do
  let(:mock_markets) { instance_double('Markets') }
  let(:mock_order_manager) { instance_double('OrderManager') }
  let(:mock_trade_roller) { instance_double('IronCondorRoller') }
  let(:mock_logger) { instance_double('Logger', info: nil) }

  let(:state_machine) do
    described_class.new(
      mock_markets,
      mock_order_manager,
      exit_prof_thresh: 0.35,
      exit_loss_thresh: 3.0,
      est_fees_per_contract: 0.0,
      est_commission_per_contract: 0.0,
      yellow_zone_delta: 0.15,
      red_zone_delta: 0.30,
      adjustment_wait_time: 900,
      trade_roller: mock_trade_roller,
      price_increment: 0.05,
      max_prof_checks: 30,
      logger: mock_logger
    )
  end

  # Helper to create a mock option leg
  def mock_option_leg(symbol:, strike:, mark: 1.0, delta: 0.10)
    instance_double(
      'OptionLeg',
      symbol: symbol,
      strike: strike,
      mark: mark,
      delta: delta
    )
  end

  # Helper to format option symbol
  def format_option_symbol(strike:, contract_type:, expiration_date: Date.today + 1)
    date_str = expiration_date.strftime('%y%m%d')
    type_char = contract_type == 'CALL' ? 'C' : 'P'
    strike_str = (strike * 1000).to_i.to_s.rjust(8, '0')
    "SPXW  #{date_str}#{type_char}#{strike_str}"
  end

  # Helper to create a mock vertical spread
  def mock_vertical_spread(short_strike:, long_strike:, contract_type: 'PUT', expiration_date: Date.today + 1)
    short_symbol = format_option_symbol(strike: short_strike, contract_type: contract_type, expiration_date: expiration_date)
    long_symbol = format_option_symbol(strike: long_strike, contract_type: contract_type, expiration_date: expiration_date)

    short_leg = mock_option_leg(
      symbol: short_symbol,
      strike: short_strike
    )
    long_leg = mock_option_leg(
      symbol: long_symbol,
      strike: long_strike
    )

    instance_double(
      'VerticalSpread',
      short_leg: short_leg,
      long_leg: long_leg,
      price: 1.50
    )
  end

  # Helper to create a mock iron condor trade
  def mock_iron_condor_trade(
    expiration_date: Date.today + 1,
    open_price: 2.0,
    contracts: 1,
    status: IronCondorTrade::OPEN_STATUS
  )
    put_spread = mock_vertical_spread(short_strike: 5900, long_strike: 5895)
    call_spread = mock_vertical_spread(short_strike: 6000, long_strike: 6005, contract_type: 'CALL')

    instance_double(
      'IronCondorTrade',
      put_spread: put_spread,
      call_spread: call_spread,
      expiration_date: expiration_date,
      open_price: open_price,
      contracts: contracts,
      status: status,
      open?: status == IronCondorTrade::OPEN_STATUS,
      closed?: status == IronCondorTrade::CLOSED_STATUS,
      max_loss_price: open_price * 3.0,
      close: nil
    )
  end

  describe '#decide' do
    let(:trade) { mock_iron_condor_trade }
    let(:prices) { { curr_contract_price: 1.5, call_spread_delta: 0.10, put_spread_delta: 0.10 } }

    it 'returns action node when reaching a leaf' do
      tree = { action: TradeStateMachine::DO_NOTHING }
      result = state_machine.decide(tree, trade, prices)
      expect(result).to eq({ action: TradeStateMachine::DO_NOTHING })
    end

    it 'follows true branch when condition is true' do
      tree = {
        condition: :working_close_order?,
        true: { action: TradeStateMachine::PROCESS_CLOSE },
        false: { action: TradeStateMachine::DO_NOTHING }
      }

      state_machine.instance_variable_set(:@close_order, instance_double('Order'))
      result = state_machine.decide(tree, trade, prices)
      expect(result).to eq({ action: TradeStateMachine::PROCESS_CLOSE })
    end

    it 'follows false branch when condition is false' do
      tree = {
        condition: :working_close_order?,
        true: { action: TradeStateMachine::PROCESS_CLOSE },
        false: { action: TradeStateMachine::DO_NOTHING }
      }

      state_machine.instance_variable_set(:@close_order, nil)
      result = state_machine.decide(tree, trade, prices)
      expect(result).to eq({ action: TradeStateMachine::DO_NOTHING })
    end

    it 'handles nested decision trees' do
      tree = {
        condition: :working_close_order?,
        true: { action: TradeStateMachine::PROCESS_CLOSE },
        false: {
          condition: :working_adjustment_order?,
          true: { action: TradeStateMachine::PROCESS_ADJUSTMENT },
          false: { action: TradeStateMachine::DO_NOTHING }
        }
      }

      state_machine.instance_variable_set(:@close_order, nil)
      state_machine.instance_variable_set(:@new_call_spread_order, nil)
      state_machine.instance_variable_set(:@new_put_spread_order, nil)

      result = state_machine.decide(tree, trade, prices)
      expect(result).to eq({ action: TradeStateMachine::DO_NOTHING })
    end
  end

  describe 'condition methods' do
    let(:trade) { mock_iron_condor_trade }
    let(:prices) { { curr_contract_price: 1.5, call_spread_delta: 0.10, put_spread_delta: 0.10 } }

    describe '#working_close_order?' do
      it 'returns true when close order exists' do
        state_machine.instance_variable_set(:@close_order, instance_double('Order'))
        expect(state_machine.send(:working_close_order?)).to be true
      end

      it 'returns false when close order is nil' do
        state_machine.instance_variable_set(:@close_order, nil)
        expect(state_machine.send(:working_close_order?)).to be false
      end
    end

    describe '#working_adjustment_order?' do
      it 'returns true when call spread order exists' do
        state_machine.instance_variable_set(:@new_call_spread_order, instance_double('Order'))
        state_machine.instance_variable_set(:@new_put_spread_order, nil)
        expect(state_machine.send(:working_adjustment_order?)).to be true
      end

      it 'returns true when put spread order exists' do
        state_machine.instance_variable_set(:@new_call_spread_order, nil)
        state_machine.instance_variable_set(:@new_put_spread_order, instance_double('Order'))
        expect(state_machine.send(:working_adjustment_order?)).to be true
      end

      it 'returns false when both orders are nil' do
        state_machine.instance_variable_set(:@new_call_spread_order, nil)
        state_machine.instance_variable_set(:@new_put_spread_order, nil)
        expect(state_machine.send(:working_adjustment_order?)).to be false
      end
    end

    describe '#call_side_tested?' do
      it 'returns true when call spread delta exceeds yellow zone' do
        prices = { call_spread_delta: 0.20, put_spread_delta: 0.10 }
        expect(state_machine.send(:call_side_tested?, trade, prices)).to be true
      end

      it 'returns false when call spread delta is below yellow zone' do
        prices = { call_spread_delta: 0.10, put_spread_delta: 0.10 }
        expect(state_machine.send(:call_side_tested?, trade, prices)).to be false
      end
    end

    describe '#put_side_tested?' do
      it 'returns true when put spread delta exceeds yellow zone' do
        prices = { call_spread_delta: 0.10, put_spread_delta: 0.20 }
        expect(state_machine.send(:put_side_tested?, trade, prices)).to be true
      end

      it 'returns false when put spread delta is below yellow zone' do
        prices = { call_spread_delta: 0.10, put_spread_delta: 0.10 }
        expect(state_machine.send(:put_side_tested?, trade, prices)).to be false
      end
    end

    describe '#adjust_call_side?' do
      it 'returns false when no timer is set' do
        state_machine.instance_variable_set(:@tested_timer, nil)
        expect(state_machine.send(:adjust_call_side?, trade, prices)).to be false
      end

      it 'returns false when timer is for PUT side' do
        state_machine.instance_variable_set(:@tested_timer, { side: 'PUT', start_time: Time.now - 1000 })
        expect(state_machine.send(:adjust_call_side?, trade, prices)).to be false
      end

      it 'returns false when not enough time has passed' do
        state_machine.instance_variable_set(:@tested_timer, { side: 'CALL', start_time: Time.now - 100 })
        expect(state_machine.send(:adjust_call_side?, trade, prices)).to be false
      end

      it 'returns true when timer is set for CALL and enough time has passed' do
        state_machine.instance_variable_set(:@tested_timer, { side: 'CALL', start_time: Time.now - 1000 })
        expect(state_machine.send(:adjust_call_side?, trade, prices)).to be true
      end
    end

    describe '#adjust_put_side?' do
      it 'returns false when no timer is set' do
        state_machine.instance_variable_set(:@tested_timer, nil)
        expect(state_machine.send(:adjust_put_side?, trade, prices)).to be false
      end

      it 'returns false when timer is for CALL side' do
        state_machine.instance_variable_set(:@tested_timer, { side: 'CALL', start_time: Time.now - 1000 })
        expect(state_machine.send(:adjust_put_side?, trade, prices)).to be false
      end

      it 'returns true when timer is set for PUT and enough time has passed' do
        state_machine.instance_variable_set(:@tested_timer, { side: 'PUT', start_time: Time.now - 1000 })
        expect(state_machine.send(:adjust_put_side?, trade, prices)).to be true
      end
    end
  end

  describe '#execute_action' do
    let(:trade) { mock_iron_condor_trade }
    let(:prices) { { curr_contract_price: 1.5, call_spread_delta: 0.10, put_spread_delta: 0.10 } }

    describe 'DO_NOTHING action' do
      it 'clears tested_timer and returns default sleep interval' do
        state_machine.instance_variable_set(:@tested_timer, { side: 'CALL', start_time: Time.now })
        action = { action: TradeStateMachine::DO_NOTHING }

        result = state_machine.send(:execute_action, action, trade, prices)

        expect(result).to eq(TradeStateMachine::DEFAULT_SLEEP_INTERVAL)
        expect(state_machine.instance_variable_get(:@tested_timer)).to be_nil
      end
    end

    describe 'START_CALL_SIDE_TIMER action' do
      it 'sets timer for CALL side and returns FIVE_SECONDS' do
        action = { action: TradeStateMachine::START_CALL_SIDE_TIMER }

        result = state_machine.send(:execute_action, action, trade, prices)

        expect(result).to eq(TradeStateMachine::FIVE_SECONDS)
        timer = state_machine.instance_variable_get(:@tested_timer)
        expect(timer[:side]).to eq('CALL')
        expect(timer[:start_time]).to be_a(Time)
      end

      it 'does not reset timer if already running for CALL side' do
        original_time = Time.now - 100
        state_machine.instance_variable_set(:@tested_timer, { side: 'CALL', start_time: original_time })
        action = { action: TradeStateMachine::START_CALL_SIDE_TIMER }

        state_machine.send(:execute_action, action, trade, prices)

        timer = state_machine.instance_variable_get(:@tested_timer)
        expect(timer[:start_time]).to eq(original_time)
      end
    end

    describe 'START_PUT_SIDE_TIMER action' do
      it 'sets timer for PUT side and returns FIVE_SECONDS' do
        action = { action: TradeStateMachine::START_PUT_SIDE_TIMER }

        result = state_machine.send(:execute_action, action, trade, prices)

        expect(result).to eq(TradeStateMachine::FIVE_SECONDS)
        timer = state_machine.instance_variable_get(:@tested_timer)
        expect(timer[:side]).to eq('PUT')
        expect(timer[:start_time]).to be_a(Time)
      end
    end

    describe 'CLOSE_FOR_PROFIT action' do
      it 'sends close order and returns NO_WAIT' do
        mock_order = instance_double('Order', status: 'WORKING')
        allow(mock_order_manager).to receive(:close_iron_condor).and_return(mock_order)
        action = { action: TradeStateMachine::CLOSE_FOR_PROFIT }

        result = state_machine.send(:execute_action, action, trade, prices)

        expect(result).to eq(TradeStateMachine::NO_WAIT)
        expect(mock_order_manager).to have_received(:close_iron_condor).with(trade, price: 1.5)
      end
    end
  end

  describe '#handle_close_order' do
    let(:trade) { mock_iron_condor_trade }

    context 'when order status is FILLED' do
      it 'closes the trade and clears close_order' do
        order_details = { price: 1.5, quantity: 1, fees: 0.5, commissions: 0.5 }
        mock_order = instance_double('Order', id: '123', status: 'FILLED', details: order_details)
        state_machine.instance_variable_set(:@close_order, mock_order)

        allow(mock_order_manager).to receive(:check_order_status).with('123').and_return(mock_order)
        expect(trade).to receive(:close).with(**order_details)

        result = state_machine.send(:handle_close_order, trade)

        expect(result).to eq(TradeStateMachine::NO_WAIT)
        expect(state_machine.instance_variable_get(:@close_order)).to be_nil
      end
    end

    context 'when order status is WORKING' do
      it 'returns FIVE_SECONDS sleep time' do
        mock_order = instance_double('Order', id: '123', status: 'WORKING')
        state_machine.instance_variable_set(:@close_order, mock_order)

        allow(mock_order_manager).to receive(:check_order_status).with('123').and_return(mock_order)

        result = state_machine.send(:handle_close_order, trade)

        expect(result).to eq(TradeStateMachine::FIVE_SECONDS)
      end
    end

    context 'when order status is CANCELED' do
      it 'clears close_order' do
        mock_order = instance_double('Order', id: '123', status: 'CANCELED')
        state_machine.instance_variable_set(:@close_order, mock_order)

        allow(mock_order_manager).to receive(:check_order_status).with('123').and_return(mock_order)

        result = state_machine.send(:handle_close_order, trade)

        expect(result).to eq(TradeStateMachine::NO_WAIT)
        expect(state_machine.instance_variable_get(:@close_order)).to be_nil
      end
    end

    context 'when order status is unexpected' do
      it 'raises an error' do
        mock_order = instance_double('Order', id: '123', status: 'FAILED')
        state_machine.instance_variable_set(:@close_order, mock_order)

        allow(mock_order_manager).to receive(:check_order_status).with('123').and_return(mock_order)

        expect {
          state_machine.send(:handle_close_order, trade)
        }.to raise_error(/Unexpected close order status: FAILED/)
      end
    end
  end

  describe '#handle_adjustment_order' do
    let(:trade) { mock_iron_condor_trade }
    let(:mock_new_call_spread) { mock_vertical_spread(short_strike: 6010, long_strike: 6015, contract_type: 'CALL') }
    let(:mock_new_put_spread) { mock_vertical_spread(short_strike: 5910, long_strike: 5905) }

    before do
      state_machine.instance_variable_set(:@new_call_spread, mock_new_call_spread)
      state_machine.instance_variable_set(:@new_put_spread, mock_new_put_spread)
    end

    context 'when both orders are FILLED' do
      it 'adjusts both spreads and clears state' do
        call_order_details = { price: 0.5, quantity: 1, fees: 0.2, commissions: 0.2, credit_debit: :debit }
        put_order_details = { price: 0.3, quantity: 1, fees: 0.2, commissions: 0.2, credit_debit: :credit }

        mock_call_order = instance_double('Order', id: '123', status: 'FILLED', details: call_order_details)
        mock_put_order = instance_double('Order', id: '456', status: 'FILLED', details: put_order_details)

        state_machine.instance_variable_set(:@new_call_spread_order, mock_call_order)
        state_machine.instance_variable_set(:@new_put_spread_order, mock_put_order)

        allow(mock_order_manager).to receive(:check_order_status).with('123').and_return(mock_call_order)
        allow(mock_order_manager).to receive(:check_order_status).with('456').and_return(mock_put_order)

        expect(trade).to receive(:adjust_call_spread).with(mock_new_call_spread, **call_order_details)
        expect(trade).to receive(:adjust_put_spread).with(mock_new_put_spread, **put_order_details)

        result = state_machine.send(:handle_adjustment_order, trade)

        expect(result).to eq(TradeStateMachine::NO_WAIT)
        expect(state_machine.instance_variable_get(:@new_call_spread)).to be_nil
        expect(state_machine.instance_variable_get(:@new_put_spread)).to be_nil
        expect(state_machine.instance_variable_get(:@new_call_spread_order)).to be_nil
        expect(state_machine.instance_variable_get(:@new_put_spread_order)).to be_nil
      end
    end

    context 'when one order is FILLED and one is WORKING' do
      it 'returns FIVE_SECONDS sleep time' do
        mock_call_order = instance_double('Order', id: '123', status: 'FILLED')
        mock_put_order = instance_double('Order', id: '456', status: 'WORKING')

        state_machine.instance_variable_set(:@new_call_spread_order, mock_call_order)
        state_machine.instance_variable_set(:@new_put_spread_order, mock_put_order)

        allow(mock_order_manager).to receive(:check_order_status).with('123').and_return(mock_call_order)
        allow(mock_order_manager).to receive(:check_order_status).with('456').and_return(mock_put_order)

        result = state_machine.send(:handle_adjustment_order, trade)

        expect(result).to eq(TradeStateMachine::FIVE_SECONDS)
      end
    end

    context 'when both orders are CANCELED' do
      it 'clears all adjustment state' do
        mock_call_order = instance_double('Order', id: '123', status: 'CANCELED')
        mock_put_order = instance_double('Order', id: '456', status: 'CANCELED')

        state_machine.instance_variable_set(:@new_call_spread_order, mock_call_order)
        state_machine.instance_variable_set(:@new_put_spread_order, mock_put_order)

        allow(mock_order_manager).to receive(:check_order_status).with('123').and_return(mock_call_order)
        allow(mock_order_manager).to receive(:check_order_status).with('456').and_return(mock_put_order)

        result = state_machine.send(:handle_adjustment_order, trade)

        expect(result).to eq(TradeStateMachine::NO_WAIT)
        expect(state_machine.instance_variable_get(:@new_call_spread)).to be_nil
        expect(state_machine.instance_variable_get(:@new_put_spread)).to be_nil
        expect(state_machine.instance_variable_get(:@new_call_spread_order)).to be_nil
        expect(state_machine.instance_variable_get(:@new_put_spread_order)).to be_nil
      end
    end
  end
end
