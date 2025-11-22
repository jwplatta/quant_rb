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
      exit_hour_thresh: 12,
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
  # Symbol format: "SPXW  251111P06745000" (expiration YYMMDD, type, strike padded to 8 digits)
  def mock_option_leg(symbol:, strike:, mark: 1.0, delta: 0.10)
    instance_double(
      'OptionLeg',
      symbol: symbol,
      strike: strike,
      mark: mark,
      delta: delta
    )
  end

  # Helper to format option symbol like "SPXW  251111P06745000"
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

  describe '#handle_close_order_status' do
    let(:trade) { mock_iron_condor_trade }

    before do
      state_machine.instance_variable_set(:@trade, trade)
      state_machine.instance_variable_set(:@action, TradeStateMachine::CLOSE_TRADE)
    end

    context 'when order status is FILLED' do
      it 'closes the trade and resets state' do
        order_details = { price: 1.5, quantity: 1, fees: 0.5, commissions: 0.5 }
        mock_order = instance_double('Order', id: '123', status: 'FILLED', details: order_details)

        state_machine.instance_variable_set(:@close_order, mock_order)

        allow(mock_order_manager).to receive(:check_order_status).with('123').and_return(mock_order)
        expect(trade).to receive(:close).with(**order_details)

        result = state_machine.handle_close_order_status

        expect(result).to eq(TradeStateMachine::NO_SLEEP)
        expect(state_machine.action).to be_nil
        expect(state_machine.instance_variable_get(:@close_order)).to be_nil
      end
    end

    context 'when order status is WORKING' do
      it 'returns FIVE_SECONDS sleep time' do
        mock_order = instance_double('Order', id: '123', status: 'WORKING')

        state_machine.instance_variable_set(:@close_order, mock_order)

        allow(mock_order_manager).to receive(:check_order_status).with('123').and_return(mock_order)

        result = state_machine.handle_close_order_status

        expect(result).to eq(TradeStateMachine::FIVE_SECONDS)
        expect(state_machine.action).to eq(TradeStateMachine::CLOSE_TRADE)
      end
    end

    context 'when order status is CANCELED' do
      it 'resets the action and close order' do
        mock_order = instance_double('Order', id: '123', status: 'CANCELED')

        state_machine.instance_variable_set(:@close_order, mock_order)

        allow(mock_order_manager).to receive(:check_order_status).with('123').and_return(mock_order)

        result = state_machine.handle_close_order_status

        expect(result).to eq(TradeStateMachine::NO_SLEEP)
        expect(state_machine.action).to be_nil
        expect(state_machine.instance_variable_get(:@close_order)).to be_nil
      end
    end

    context 'when order status is unexpected' do
      it 'raises an error' do
        mock_order = instance_double('Order', id: '123', status: 'FAILED')

        state_machine.instance_variable_set(:@close_order, mock_order)

        allow(mock_order_manager).to receive(:check_order_status).with('123').and_return(mock_order)

        expect {
          state_machine.handle_close_order_status
        }.to raise_error(/Unexpected close order status: FAILED/)
      end
    end
  end

  describe '#handle_adjustment_order_status' do
    let(:trade) { mock_iron_condor_trade }
    let(:mock_new_call_spread) { mock_vertical_spread(short_strike: 6010, long_strike: 6015, contract_type: 'CALL') }
    let(:mock_new_put_spread) { mock_vertical_spread(short_strike: 5910, long_strike: 5905) }

    before do
      state_machine.instance_variable_set(:@trade, trade)
      state_machine.instance_variable_set(:@action, TradeStateMachine::ADJUST_TRADE)
      state_machine.instance_variable_set(:@new_call_spread, mock_new_call_spread)
      state_machine.instance_variable_set(:@new_put_spread, mock_new_put_spread)
    end

    context 'when both orders are FILLED' do
      it 'adjusts both spreads and resets state' do
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

        result = state_machine.handle_adjustment_order_status

        expect(result).to eq(TradeStateMachine::NO_SLEEP)
        expect(state_machine.action).to be_nil
        expect(state_machine.instance_variable_get(:@new_call_spread)).to be_nil
        expect(state_machine.instance_variable_get(:@new_put_spread)).to be_nil
        expect(state_machine.instance_variable_get(:@new_call_spread_order)).to be_nil
        expect(state_machine.instance_variable_get(:@new_put_spread_order)).to be_nil
      end
    end

    context 'when call order is FILLED and put order is CANCELED' do
      it 'resends the put order' do
        put_order_details = { price: 0.3, quantity: 1 }

        mock_call_order = instance_double('Order', id: '123', status: 'FILLED')
        mock_put_order = instance_double('Order', id: '456', status: 'CANCELED', details: put_order_details)

        state_machine.instance_variable_set(:@new_call_spread_order, mock_call_order)
        state_machine.instance_variable_set(:@new_put_spread_order, mock_put_order)

        allow(mock_order_manager).to receive(:check_order_status).with('123').and_return(mock_call_order)
        allow(mock_order_manager).to receive(:check_order_status).with('456').and_return(mock_put_order)

        expect(mock_order_manager).to receive(:send_order).with(put_order_details)

        result = state_machine.handle_adjustment_order_status

        expect(result).to eq(TradeStateMachine::NO_SLEEP)
      end
    end

    context 'when call order is CANCELED and put order is FILLED' do
      it 'resends the call order' do
        call_order_details = { price: 0.5, quantity: 1 }

        mock_call_order = instance_double('Order', id: '123', status: 'CANCELED', details: call_order_details)
        mock_put_order = instance_double('Order', id: '456', status: 'FILLED')

        state_machine.instance_variable_set(:@new_call_spread_order, mock_call_order)
        state_machine.instance_variable_set(:@new_put_spread_order, mock_put_order)

        allow(mock_order_manager).to receive(:check_order_status).with('123').and_return(mock_call_order)
        allow(mock_order_manager).to receive(:check_order_status).with('456').and_return(mock_put_order)

        expect(mock_order_manager).to receive(:send_order).with(call_order_details)

        result = state_machine.handle_adjustment_order_status

        expect(result).to eq(TradeStateMachine::NO_SLEEP)
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

        result = state_machine.handle_adjustment_order_status

        expect(result).to eq(TradeStateMachine::FIVE_SECONDS)
      end

      it 'handles WORKING call and FILLED put' do
        mock_call_order = instance_double('Order', id: '123', status: 'WORKING')
        mock_put_order = instance_double('Order', id: '456', status: 'FILLED')

        state_machine.instance_variable_set(:@new_call_spread_order, mock_call_order)
        state_machine.instance_variable_set(:@new_put_spread_order, mock_put_order)

        allow(mock_order_manager).to receive(:check_order_status).with('123').and_return(mock_call_order)
        allow(mock_order_manager).to receive(:check_order_status).with('456').and_return(mock_put_order)

        result = state_machine.handle_adjustment_order_status

        expect(result).to eq(TradeStateMachine::FIVE_SECONDS)
      end
    end

    context 'when both orders are CANCELED' do
      it 'resets all adjustment state' do
        mock_call_order = instance_double('Order', id: '123', status: 'CANCELED')
        mock_put_order = instance_double('Order', id: '456', status: 'CANCELED')

        state_machine.instance_variable_set(:@new_call_spread_order, mock_call_order)
        state_machine.instance_variable_set(:@new_put_spread_order, mock_put_order)

        allow(mock_order_manager).to receive(:check_order_status).with('123').and_return(mock_call_order)
        allow(mock_order_manager).to receive(:check_order_status).with('456').and_return(mock_put_order)

        result = state_machine.handle_adjustment_order_status

        expect(result).to eq(TradeStateMachine::NO_SLEEP)
        expect(state_machine.action).to be_nil
        expect(state_machine.instance_variable_get(:@new_call_spread)).to be_nil
        expect(state_machine.instance_variable_get(:@new_put_spread)).to be_nil
        expect(state_machine.instance_variable_get(:@new_call_spread_order)).to be_nil
        expect(state_machine.instance_variable_get(:@new_put_spread_order)).to be_nil
      end
    end
  end
end
