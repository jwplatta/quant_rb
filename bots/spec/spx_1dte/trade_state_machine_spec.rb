# frozen_string_literal: true

require 'spec_helper'
require_relative '../../spx_1dte/trade_state_machine'
require_relative '../../spx_1dte/trade'
require_relative '../../spx_1dte/data_objects'
require_relative '../../spx_1dte/constants'

RSpec.describe TradeStateMachine do
  let(:strategy_pricer) { instance_double('StrategyPricer') }
  let(:mock_order_manager) { instance_double('OrderManager') }
  let(:mock_trade_roller) { instance_double('IronCondorRoller') }
  let(:mock_logger) { instance_double('Logger', info: nil) }

  let(:state_machine) do
    described_class.new(
      strategy_pricer,
      mock_order_manager,
      yellow_zone_delta: 0.15,
      red_zone_delta: 0.30,
      adjustment_wait_time: 900,
      trade_roller: mock_trade_roller,
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
  def format_option_symbol(strike:, contract_type:, expiration_date: Date.today)
    date_str = expiration_date.strftime('%y%m%d')
    type_char = contract_type == 'CALL' ? 'C' : 'P'
    strike_str = (strike * 1000).to_i.to_s.rjust(8, '0')
    "SPXW  #{date_str}#{type_char}#{strike_str}"
  end

  # Helper to create a mock vertical spread
  def mock_vertical_spread(short_strike:, long_strike:, contract_type: 'PUT', expiration_date: Date.today, price: 1.50, delta: 0.10)
    short_symbol = format_option_symbol(strike: short_strike, contract_type: contract_type, expiration_date: expiration_date)
    long_symbol = format_option_symbol(strike: long_strike, contract_type: contract_type, expiration_date: expiration_date)

    short_leg = mock_option_leg(
      symbol: short_symbol,
      strike: short_strike,
      delta: delta
    )
    long_leg = mock_option_leg(
      symbol: long_symbol,
      strike: long_strike,
      delta: delta
    )

    double(
      'VerticalSpread',
      short_leg: short_leg,
      long_leg: long_leg,
      price: price,
      delta: delta,
      contract_type: contract_type,
      expiration_date: expiration_date
    ).tap do |spread|
      allow(spread).to receive(:is_a?).with(IronCondor).and_return(false)
      allow(spread).to receive(:is_a?).with(VerticalSpread).and_return(true)
    end
  end

  # Helper to create a mock iron condor strategy
  def mock_iron_condor(
    call_spread_price: 1.0,
    put_spread_price: 1.0,
    call_spread_delta: 0.10,
    put_spread_delta: 0.10,
    expiration_date: Date.today
  )
    call_spread = mock_vertical_spread(
      short_strike: 6010,
      long_strike: 6015,
      contract_type: 'CALL',
      price: call_spread_price,
      delta: call_spread_delta,
      expiration_date: expiration_date
    )

    put_spread = mock_vertical_spread(
      short_strike: 5910,
      long_strike: 5905,
      contract_type: 'PUT',
      price: put_spread_price,
      delta: put_spread_delta,
      expiration_date: expiration_date
    )

    double(
      'IronCondor',
      call_spread: call_spread,
      put_spread: put_spread,
      price: call_spread_price + put_spread_price,
      expiration_date: expiration_date
    ).tap do |iron_condor|
      allow(iron_condor).to receive(:is_a?).with(IronCondor).and_return(true)
      allow(iron_condor).to receive(:is_a?).with(VerticalSpread).and_return(false)
    end
  end

  # Helper to create a mock trade
  def mock_trade(
    id: '123',
    status: Trade::OPEN_STATUS,
    exit_prof_price: 0.5,
    max_loss_price: 6.0,
    total_credit_debit: 2.0
  )
    instance_double(
      'Trade',
      id: id,
      status: status,
      open?: status == Trade::OPEN_STATUS,
      closed?: status == Trade::CLOSED_STATUS,
      exit_prof_price: exit_prof_price,
      max_loss_price: max_loss_price,
      total_credit_debit: total_credit_debit,
      save_event: nil
    )
  end

  describe '#decide' do
    let(:trade) { mock_trade }

    before do
      state_machine.set_monitoring_window(
        Time.now - 3600,
        Time.now + 3600,
        Time.now + 1800
      )
    end

    context 'when there is a working order' do
      it 'returns WAIT_FOR_WORKING_ORDER action' do
        state_machine.instance_variable_set(:@last_action, EventTypes::CLOSE_IRON_CONDOR)
        strategy = mock_iron_condor

        result = state_machine.decide(trade, strategy)

        expect(result).to eq(TradeStateMachine::WAIT_FOR_WORKING_ORDER)
      end
    end

    context 'when iron condor should exit for profit' do
      it 'returns CLOSE_IRON_CONDOR action' do
        strategy = mock_iron_condor(
          call_spread_price: 0.3,
          put_spread_price: 0.2
        )
        trade = mock_trade(exit_prof_price: 0.5)

        result = state_machine.decide(trade, strategy)

        expect(result).to eq(EventTypes::CLOSE_IRON_CONDOR)
      end
    end

    context 'when iron condor should exit for loss' do
      it 'returns CLOSE_IRON_CONDOR action' do
        strategy = mock_iron_condor(
          call_spread_price: 3.0,
          put_spread_price: 3.0,
          expiration_date: Date.today
        )
        trade = mock_trade(max_loss_price: 6.0)

        result = state_machine.decide(trade, strategy)

        expect(result).to eq(EventTypes::CLOSE_IRON_CONDOR)
      end
    end

    context 'when call spread should exit for profit' do
      it 'returns CLOSE_CALL_SPREAD action' do
        call_spread = mock_vertical_spread(
          short_strike: 6010,
          long_strike: 6015,
          contract_type: 'CALL',
          price: 0.2
        )
        trade = mock_trade(exit_prof_price: 0.5)

        result = state_machine.decide(trade, call_spread)

        expect(result).to eq(EventTypes::CLOSE_CALL_SPREAD)
      end
    end

    context 'when put spread should exit for profit' do
      it 'returns CLOSE_PUT_SPREAD action' do
        put_spread = mock_vertical_spread(
          short_strike: 5910,
          long_strike: 5905,
          contract_type: 'PUT',
          price: 0.2
        )
        trade = mock_trade(exit_prof_price: 0.5)

        result = state_machine.decide(trade, put_spread)

        expect(result).to eq(EventTypes::CLOSE_PUT_SPREAD)
      end
    end

    context 'when nothing should happen' do
      it 'returns DO_NOTHING action' do
        strategy = mock_iron_condor
        trade = mock_trade

        result = state_machine.decide(trade, strategy)

        expect(result).to eq(TradeStateMachine::DO_NOTHING)
      end
    end
  end

  describe 'condition methods' do
    let(:trade) { mock_trade }

    describe '#working_order?' do
      it 'returns true when last_action is CLOSE_IRON_CONDOR' do
        state_machine.instance_variable_set(:@last_action, EventTypes::CLOSE_IRON_CONDOR)
        strategy = mock_iron_condor

        expect(state_machine.send(:working_order?, trade, strategy)).to be true
      end

      it 'returns true when last_action is CLOSE_CALL_SPREAD' do
        state_machine.instance_variable_set(:@last_action, EventTypes::CLOSE_CALL_SPREAD)
        strategy = mock_iron_condor

        expect(state_machine.send(:working_order?, trade, strategy)).to be true
      end

      it 'returns true when last_action is CLOSE_PUT_SPREAD' do
        state_machine.instance_variable_set(:@last_action, EventTypes::CLOSE_PUT_SPREAD)
        strategy = mock_iron_condor

        expect(state_machine.send(:working_order?, trade, strategy)).to be true
      end

      it 'returns false when last_action is nil' do
        state_machine.instance_variable_set(:@last_action, nil)
        strategy = mock_iron_condor

        expect(state_machine.send(:working_order?, trade, strategy)).to be false
      end

      it 'returns false when last_action is DO_NOTHING' do
        state_machine.instance_variable_set(:@last_action, TradeStateMachine::DO_NOTHING)
        strategy = mock_iron_condor

        expect(state_machine.send(:working_order?, trade, strategy)).to be false
      end
    end

    describe '#exit_iron_condor?' do
      it 'returns true when strategy is IronCondor and should exit for profit' do
        strategy = mock_iron_condor(call_spread_price: 0.3, put_spread_price: 0.2)
        trade = mock_trade(exit_prof_price: 0.5)

        expect(state_machine.send(:exit_iron_condor?, trade, strategy)).to be true
      end

      it 'returns false when strategy is not IronCondor' do
        strategy = mock_vertical_spread(short_strike: 6010, long_strike: 6015, contract_type: 'CALL')
        trade = mock_trade

        expect(state_machine.send(:exit_iron_condor?, trade, strategy)).to be false
      end
    end

    describe '#exit_call_spread?' do
      it 'returns true when iron condor call spread should exit' do
        strategy = mock_iron_condor(call_spread_price: 0.2)
        trade = mock_trade(exit_prof_price: 0.5)

        expect(state_machine.send(:exit_call_spread?, trade, strategy)).to be true
      end

      it 'returns true when standalone call spread should exit' do
        strategy = mock_vertical_spread(
          short_strike: 6010,
          long_strike: 6015,
          contract_type: 'CALL',
          price: 0.2
        )
        trade = mock_trade(exit_prof_price: 0.5)

        expect(state_machine.send(:exit_call_spread?, trade, strategy)).to be true
      end

      it 'returns false when strategy is put spread' do
        strategy = mock_vertical_spread(
          short_strike: 5910,
          long_strike: 5905,
          contract_type: 'PUT',
          price: 0.2
        )
        trade = mock_trade(exit_prof_price: 0.5)

        expect(state_machine.send(:exit_call_spread?, trade, strategy)).to be false
      end
    end

    describe '#exit_put_spread?' do
      it 'returns true when iron condor put spread should exit' do
        strategy = mock_iron_condor(put_spread_price: 0.2)
        trade = mock_trade(exit_prof_price: 0.5)

        expect(state_machine.send(:exit_put_spread?, trade, strategy)).to be true
      end

      it 'returns true when standalone put spread should exit' do
        strategy = mock_vertical_spread(
          short_strike: 5910,
          long_strike: 5905,
          contract_type: 'PUT',
          price: 0.2
        )
        trade = mock_trade(exit_prof_price: 0.5)

        expect(state_machine.send(:exit_put_spread?, trade, strategy)).to be true
      end

      it 'returns false when strategy is call spread' do
        strategy = mock_vertical_spread(
          short_strike: 6010,
          long_strike: 6015,
          contract_type: 'CALL',
          price: 0.2
        )
        trade = mock_trade(exit_prof_price: 0.5)

        expect(state_machine.send(:exit_put_spread?, trade, strategy)).to be false
      end
    end

    describe '#exit_profit?' do
      it 'returns true when iron condor price is at or below profit target' do
        strategy = mock_iron_condor(call_spread_price: 0.3, put_spread_price: 0.2)
        trade = mock_trade(exit_prof_price: 0.5)

        expect(state_machine.send(:exit_profit?, trade, strategy)).to be true
      end

      it 'returns true when vertical spread price is at or below 50% of profit target' do
        strategy = mock_vertical_spread(short_strike: 5910, long_strike: 5905, price: 0.2)
        trade = mock_trade(exit_prof_price: 0.5)

        expect(state_machine.send(:exit_profit?, trade, strategy)).to be true
      end

      it 'returns false when price is above profit target' do
        strategy = mock_iron_condor(call_spread_price: 0.6, put_spread_price: 0.5)
        trade = mock_trade(exit_prof_price: 0.5)

        expect(state_machine.send(:exit_profit?, trade, strategy)).to be false
      end
    end

    describe '#exit_loss?' do
      it 'returns true when price exceeds max loss and expires today' do
        strategy = mock_iron_condor(
          call_spread_price: 3.0,
          put_spread_price: 3.0,
          expiration_date: Date.today
        )
        trade = mock_trade(max_loss_price: 5.0)

        expect(state_machine.send(:exit_loss?, trade, strategy)).to be true
      end

      it 'returns false when price exceeds max loss but does not expire today' do
        strategy = mock_iron_condor(
          call_spread_price: 3.0,
          put_spread_price: 3.0,
          expiration_date: Date.today + 1
        )
        trade = mock_trade(max_loss_price: 5.0)

        expect(state_machine.send(:exit_loss?, trade, strategy)).to be false
      end

      it 'returns false when price is below max loss' do
        strategy = mock_iron_condor(
          call_spread_price: 1.0,
          put_spread_price: 1.0,
          expiration_date: Date.today
        )
        trade = mock_trade(max_loss_price: 5.0)

        expect(state_machine.send(:exit_loss?, trade, strategy)).to be false
      end
    end

    describe '#exit_late_profitable?' do
      before do
        state_machine.set_monitoring_window(
          Time.now - 3600,
          Time.now + 3600,
          Time.now - 100
        )
      end

      it 'returns true when past exit time and price is profitable' do
        strategy = mock_iron_condor(
          call_spread_price: 0.5,
          put_spread_price: 0.5,
          expiration_date: Date.today
        )
        trade = mock_trade(total_credit_debit: 2.0)

        expect(state_machine.send(:exit_late_profitable?, trade, strategy)).to be true
      end

      it 'returns false when past exit time but price is not profitable' do
        strategy = mock_iron_condor(
          call_spread_price: 1.5,
          put_spread_price: 1.5,
          expiration_date: Date.today
        )
        trade = mock_trade(total_credit_debit: 2.0)

        expect(state_machine.send(:exit_late_profitable?, trade, strategy)).to be false
      end

      it 'returns false when not past exit time' do
        state_machine.set_monitoring_window(
          Time.now - 3600,
          Time.now + 3600,
          Time.now + 100
        )
        strategy = mock_iron_condor(
          call_spread_price: 0.5,
          put_spread_price: 0.5,
          expiration_date: Date.today
        )
        trade = mock_trade(total_credit_debit: 2.0)

        expect(state_machine.send(:exit_late_profitable?, trade, strategy)).to be false
      end
    end

    describe '#exit_late?' do
      before do
        state_machine.set_monitoring_window(
          Time.now - 7200,
          Time.now + 3600,
          Time.now - 3700
        )
      end

      it 'returns true when one hour past exit time and expires today' do
        strategy = mock_iron_condor(expiration_date: Date.today)

        expect(state_machine.send(:exit_late?, strategy)).to be true
      end

      it 'returns false when not one hour past exit time' do
        state_machine.set_monitoring_window(
          Time.now - 3600,
          Time.now + 3600,
          Time.now - 100
        )
        strategy = mock_iron_condor(expiration_date: Date.today)

        expect(state_machine.send(:exit_late?, strategy)).to be false
      end

      it 'returns false when does not expire today' do
        strategy = mock_iron_condor(expiration_date: Date.today + 1)

        expect(state_machine.send(:exit_late?, strategy)).to be false
      end
    end
  end

  describe '#execute_action' do
    let(:trade) { mock_trade }

    describe 'DO_NOTHING action' do
      it 'sets last_action and returns DEFAULT_WAIT' do
        strategy = mock_iron_condor

        result = state_machine.send(:execute_action, TradeStateMachine::DO_NOTHING, trade, strategy)

        expect(result).to eq(TradeStateMachine::DEFAULT_WAIT)
        expect(state_machine.instance_variable_get(:@last_action)).to eq(TradeStateMachine::DO_NOTHING)
      end
    end

    describe 'CLOSE_IRON_CONDOR action' do
      it 'sends close order and returns NO_WAIT' do
        strategy = mock_iron_condor
        mock_order = instance_double('Order', id: '123', status: OrderStatuses::WORKING)
        allow(mock_order_manager).to receive(:close_iron_condor).and_return(mock_order)

        result = state_machine.send(:execute_action, EventTypes::CLOSE_IRON_CONDOR, trade, strategy)

        expect(result).to eq(TradeStateMachine::NO_WAIT)
        expect(mock_order_manager).to have_received(:close_iron_condor).with(strategy)
        expect(state_machine.instance_variable_get(:@last_action)).to eq(EventTypes::CLOSE_IRON_CONDOR)
      end

      it 'raises error when order status is not WORKING' do
        strategy = mock_iron_condor
        mock_order = instance_double('Order', id: '123', status: OrderStatuses::FILLED)
        allow(mock_order_manager).to receive(:close_iron_condor).and_return(mock_order)

        expect {
          state_machine.send(:execute_action, EventTypes::CLOSE_IRON_CONDOR, trade, strategy)
        }.to raise_error(/Unexpected order status when closing trade/)
      end
    end

    describe 'CLOSE_CALL_SPREAD action' do
      it 'sends close spread order for iron condor call spread and returns NO_WAIT' do
        strategy = mock_iron_condor
        mock_order = instance_double('Order', id: '123', status: OrderStatuses::WORKING)
        allow(mock_order_manager).to receive(:close_spread).and_return(mock_order)

        result = state_machine.send(:execute_action, EventTypes::CLOSE_CALL_SPREAD, trade, strategy)

        expect(result).to eq(TradeStateMachine::NO_WAIT)
        expect(mock_order_manager).to have_received(:close_spread).with(strategy.call_spread)
        expect(state_machine.instance_variable_get(:@last_action)).to eq(EventTypes::CLOSE_CALL_SPREAD)
      end

      it 'sends close spread order for standalone call spread' do
        strategy = mock_vertical_spread(
          short_strike: 6010,
          long_strike: 6015,
          contract_type: 'CALL'
        )
        mock_order = instance_double('Order', id: '123', status: OrderStatuses::WORKING)
        allow(mock_order_manager).to receive(:close_spread).and_return(mock_order)

        result = state_machine.send(:execute_action, EventTypes::CLOSE_CALL_SPREAD, trade, strategy)

        expect(result).to eq(TradeStateMachine::NO_WAIT)
        expect(mock_order_manager).to have_received(:close_spread).with(strategy)
      end
    end

    describe 'CLOSE_PUT_SPREAD action' do
      it 'sends close spread order for iron condor put spread and returns NO_WAIT' do
        strategy = mock_iron_condor
        mock_order = instance_double('Order', id: '123', status: OrderStatuses::WORKING)
        allow(mock_order_manager).to receive(:close_spread).and_return(mock_order)

        result = state_machine.send(:execute_action, EventTypes::CLOSE_PUT_SPREAD, trade, strategy)

        expect(result).to eq(TradeStateMachine::NO_WAIT)
        expect(mock_order_manager).to have_received(:close_spread).with(strategy.put_spread)
        expect(state_machine.instance_variable_get(:@last_action)).to eq(EventTypes::CLOSE_PUT_SPREAD)
      end

      it 'sends close spread order for standalone put spread' do
        strategy = mock_vertical_spread(
          short_strike: 5910,
          long_strike: 5905,
          contract_type: 'PUT'
        )
        mock_order = instance_double('Order', id: '123', status: OrderStatuses::WORKING)
        allow(mock_order_manager).to receive(:close_spread).and_return(mock_order)

        result = state_machine.send(:execute_action, EventTypes::CLOSE_PUT_SPREAD, trade, strategy)

        expect(result).to eq(TradeStateMachine::NO_WAIT)
        expect(mock_order_manager).to have_received(:close_spread).with(strategy)
      end
    end

    describe 'WAIT_FOR_WORKING_ORDER action' do
      it 'delegates to handle_close_order' do
        strategy = mock_iron_condor
        mock_order = instance_double('Order', id: '123', status: OrderStatuses::WORKING)
        state_machine.instance_variable_set(:@working_order, mock_order)
        state_machine.instance_variable_set(:@last_action, EventTypes::CLOSE_IRON_CONDOR)

        allow(mock_order_manager).to receive(:check_order_status).and_return(mock_order)

        result = state_machine.send(:execute_action, TradeStateMachine::WAIT_FOR_WORKING_ORDER, trade, strategy)

        expect(result).to eq(TradeStateMachine::FIVE_SECONDS)
      end
    end
  end

  describe '#handle_close_order' do
    let(:trade) { mock_trade }

    context 'when order status is FILLED' do
      it 'saves event to trade and clears working order' do
        order_details = { price: 1.5, quantity: 1, fees: 0.5, commissions: 0.5 }
        mock_order = instance_double('Order', id: '123', status: OrderStatuses::FILLED, details: order_details)
        state_machine.instance_variable_set(:@working_order, mock_order)
        state_machine.instance_variable_set(:@last_action, EventTypes::CLOSE_IRON_CONDOR)

        allow(mock_order_manager).to receive(:check_order_status).with('123').and_return(mock_order)
        expect(trade).to receive(:save_event).with(EventTypes::CLOSE_IRON_CONDOR, **order_details)

        result = state_machine.send(:handle_close_order, trade)

        expect(result).to eq(TradeStateMachine::NO_WAIT)
        expect(state_machine.instance_variable_get(:@working_order)).to be_nil
        expect(state_machine.instance_variable_get(:@last_action)).to be_nil
      end
    end

    context 'when order status is WORKING' do
      it 'returns FIVE_SECONDS sleep time' do
        mock_order = instance_double('Order', id: '123', status: OrderStatuses::WORKING)
        state_machine.instance_variable_set(:@working_order, mock_order)

        allow(mock_order_manager).to receive(:check_order_status).with('123').and_return(mock_order)

        result = state_machine.send(:handle_close_order, trade)

        expect(result).to eq(TradeStateMachine::FIVE_SECONDS)
      end
    end

    context 'when order status is CANCELED' do
      it 'clears working order and last_action' do
        mock_order = instance_double('Order', id: '123', status: OrderStatuses::CANCELED)
        state_machine.instance_variable_set(:@working_order, mock_order)
        state_machine.instance_variable_set(:@last_action, EventTypes::CLOSE_IRON_CONDOR)

        allow(mock_order_manager).to receive(:check_order_status).with('123').and_return(mock_order)

        result = state_machine.send(:handle_close_order, trade)

        expect(result).to eq(TradeStateMachine::NO_WAIT)
        expect(state_machine.instance_variable_get(:@working_order)).to be_nil
        expect(state_machine.instance_variable_get(:@last_action)).to be_nil
      end
    end

    context 'when order status is unexpected' do
      it 'raises an error' do
        mock_order = instance_double('Order', id: '123', status: 'FAILED')
        state_machine.instance_variable_set(:@working_order, mock_order)

        allow(mock_order_manager).to receive(:check_order_status).with('123').and_return(mock_order)

        expect {
          state_machine.send(:handle_close_order, trade)
        }.to raise_error(/Unexpected close order status: FAILED/)
      end
    end
  end
end
