# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'

RSpec.describe OptionsTrader::Trades::Trade do
  let(:mock_strategy) do
    double('Strategy',
      type: 'ironcondor',
      to_h: {
        type: 'ironcondor',
        underlying_symbol: 'SPY',
        quantity: 1,
        credit: 2.50
      }
    )
  end

  let(:mock_strategy_adjuster) do
    double('StrategyAdjuster',
      to_h: {
        type: 'test_adjuster',
        params: { some: 'value' }
      }
    )
  end

  let(:mock_trade_journal) do
    double('TradeJournal',
      log: nil
    )
  end

  let(:mock_order_manager) do
    double('OrderManager',
      to_h: {
        order_id: 'test-order-123',
        order_status: 'FILLED',
        order_price: 2.50
      },
      from_h: nil
    )
  end

  let(:mock_progress) do
    double('TradeProgress',
      profit_thresh: 0.65,
      loss_thresh: -2.0,
      to_h: {
        progress_perc: 25.0,
        current_pnl: 50.0,
        profit_thresh: 0.65,
        loss_thresh: -2.0
      },
      from_h: nil
    )
  end

  let(:mock_risk_monitor) do
    double('RiskMonitor',
      green_delta: 0.16,
      yellow_delta: 0.26,
      to_h: {
        green_delta: 0.16,
        yellow_delta: 0.26
      },
      from_h: nil
    )
  end

  before do
    allow(OptionsTrader::Trades::TradeJournal).to receive(:read_or_init).and_return(mock_trade_journal)
    allow(OptionsTrader::Trades::OrderManager).to receive(:new).and_return(mock_order_manager)
    allow(OptionsTrader::TradeProgress).to receive(:new).and_return(mock_progress)
    allow(OptionsTrader::Trades::RiskMonitor).to receive(:new).and_return(mock_risk_monitor)
  end

  describe '#to_h' do
    let(:trade) do
      described_class.new(
        trade_id: 'test-trade-123',
        strategy: mock_strategy,
        paper_trading: true,
        strategy_type: 'ironcondor',
        underlying_symbol: 'SPY',
        expiration_date: Date.new(2025, 6, 20),
        short_delta: 0.08,
        max_spread: 15.0,
        min_credit: 150.0,
        min_open_interest: 10,
        dist_from_strike: 0.02,
        settlement_type: 'PM',
        option_root: 'SPY',
        quantity: 2,
        profit_thresh: 0.70,
        loss_thresh: -2.5,
        green_delta: 0.18,
        yellow_delta: 0.28,
        strategy_adjuster: mock_strategy_adjuster,
        timestamp: Time.new(2025, 6, 20, 10, 30, 0)
      )
    end

    it 'returns a hash with all trade attributes' do
      result = trade.to_h

      expect(result).to be_a(Hash)
      expect(result[:trade_id]).to eq('test-trade-123')
      expect(result[:paper_trading]).to be true
      expect(result[:trade_state]).to eq('NO_TRADE_FOUND')
      expect(result[:strategy]).to eq(mock_strategy.to_h)
      expect(result[:timestamp]).to eq(Time.new(2025, 6, 20, 10, 30, 0))
    end

    it 'includes strategy attributes' do
      result = trade.to_h

      expect(result[:strategy_type]).to eq('ironcondor')
      expect(result[:underlying_symbol]).to eq('SPY')
      expect(result[:expiration_date]).to eq(Date.new(2025, 6, 20))
      expect(result[:short_delta]).to eq(0.08)
      expect(result[:max_spread]).to eq(15.0)
      expect(result[:min_credit]).to eq(150.0)
      expect(result[:min_open_interest]).to eq(10)
      expect(result[:dist_from_strike]).to eq(0.02)
      expect(result[:settlement_type]).to eq('PM')
      expect(result[:option_root]).to eq('SPY')
      expect(result[:quantity]).to eq(2)
    end

    it 'includes trade management attributes' do
      result = trade.to_h

      expect(result[:profit_thresh]).to eq(0.65) # From mock_progress
      expect(result[:loss_thresh]).to eq(-2.0)   # From mock_progress
      expect(result[:green_delta]).to eq(0.16)   # From mock_risk_monitor
      expect(result[:yellow_delta]).to eq(0.26)  # From mock_risk_monitor
      expect(result[:strategy_adjuster]).to eq(mock_strategy_adjuster.to_h)
    end

    it 'includes processing attributes' do
      result = trade.to_h

      expect(result[:find_trade_attempts]).to eq(0)
      expect(result[:working_cnt]).to eq(0)
    end

    it 'includes nested object data' do
      result = trade.to_h

      expect(result[:order]).to eq(mock_order_manager.to_h)
      expect(result[:progress]).to eq(mock_progress.to_h)
    end

    it 'handles nil strategy gracefully' do
      trade_without_strategy = described_class.new(
        trade_id: 'test-trade-456',
        strategy: nil,
        strategy_type: 'callspread'
      )

      result = trade_without_strategy.to_h

      expect(result[:strategy]).to be_nil
      expect(result[:strategy_type]).to eq('callspread')
    end

    it 'handles nil strategy_adjuster gracefully' do
      trade_without_adjuster = described_class.new(
        trade_id: 'test-trade-789',
        strategy_adjuster: nil
      )

      result = trade_without_adjuster.to_h

      expect(result[:strategy_adjuster]).to be_nil
    end
  end

  describe '.from_h' do
    let(:trade_hash) do
      {
        trade_id: 'restored-trade-123',
        paper_trading: true,
        trade_state: 'TRADE_ENTERED',
        strategy: {
          type: 'ironcondor',
          underlying_symbol: 'SPY',
          quantity: 1,
          credit: 2.50
        },
        timestamp: '2025-06-20T10:30:00Z',
        # Strategy attributes
        strategy_type: 'ironcondor',
        underlying_symbol: 'SPY',
        expiration_date: Date.new(2025, 6, 20),
        short_delta: 0.08,
        max_spread: 15.0,
        min_credit: 150.0,
        min_open_interest: 10,
        dist_from_strike: 0.02,
        settlement_type: 'PM',
        option_root: 'SPY',
        quantity: 2,
        # Trade management attributes
        profit_thresh: 0.70,
        loss_thresh: -2.5,
        green_delta: 0.18,
        yellow_delta: 0.28,
        # Processing attributes
        find_trade_attempts: 5,
        working_cnt: 3,
        # Nested objects
        order: {
          order_id: 'restored-order-456',
          order_status: 'WORKING',
          order_price: 2.75
        },
        progress: {
          progress_perc: 45.0,
          current_pnl: 125.0,
          profit_thresh: 0.70,
          loss_thresh: -2.5
        }
      }
    end

    before do
      allow(described_class).to receive(:create_strategy_from_h).and_return(mock_strategy)
    end

    it 'reconstructs a trade from hash data' do
      trade = described_class.from_h(trade_hash)

      expect(trade).to be_a(described_class)
      expect(trade.trade_id).to eq('restored-trade-123')
      expect(trade.paper_trading).to be true
      expect(trade.current_state).to eq('TRADE_ENTERED')
      expect(trade.strategy).to eq(mock_strategy)
    end

    it 'restores strategy attributes' do
      trade = described_class.from_h(trade_hash)

      expect(trade.instance_variable_get(:@strategy_type)).to eq('ironcondor')
      expect(trade.instance_variable_get(:@underlying_symbol)).to eq('SPY')
      expect(trade.instance_variable_get(:@expiration_date)).to eq(Date.new(2025, 6, 20))
      expect(trade.instance_variable_get(:@short_delta)).to eq(0.08)
      expect(trade.instance_variable_get(:@max_spread)).to eq(15.0)
      expect(trade.instance_variable_get(:@min_credit)).to eq(150.0)
      expect(trade.instance_variable_get(:@min_open_interest)).to eq(10)
      expect(trade.instance_variable_get(:@dist_from_strike)).to eq(0.02)
      expect(trade.instance_variable_get(:@settlement_type)).to eq('PM')
      expect(trade.instance_variable_get(:@option_root)).to eq('SPY')
      expect(trade.instance_variable_get(:@quantity)).to eq(2)
    end

    it 'restores processing attributes' do
      trade = described_class.from_h(trade_hash)

      expect(trade.find_trade_attempts).to eq(5)
      expect(trade.working_cnt).to eq(3)
    end

    it 'restores nested object states' do
      trade = described_class.from_h(trade_hash)

      expect(mock_order_manager).to have_received(:from_h).with(trade_hash[:order])
      expect(mock_progress).to have_received(:from_h).with(trade_hash[:progress])
      expect(mock_risk_monitor).to have_received(:from_h).with(trade_hash)
    end

    it 'uses default values when attributes are missing' do
      minimal_hash = {
        trade_id: 'minimal-trade'
      }

      trade = described_class.from_h(minimal_hash)

      expect(trade.trade_id).to eq('minimal-trade')
      expect(trade.paper_trading).to be false
      expect(trade.current_state).to eq('NO_TRADE_FOUND')
      expect(trade.instance_variable_get(:@short_delta)).to eq(0.05)
      expect(trade.instance_variable_get(:@max_spread)).to eq(10.0)
      expect(trade.instance_variable_get(:@min_credit)).to eq(100.0)
      expect(trade.instance_variable_get(:@quantity)).to eq(1)
    end

    it 'handles missing strategy gracefully' do
      hash_without_strategy = trade_hash.dup
      hash_without_strategy.delete(:strategy)

      trade = described_class.from_h(hash_without_strategy)

      expect(trade.strategy).to be_nil
      expect(trade.instance_variable_get(:@strategy_type)).to eq('ironcondor')
    end

    it 'handles missing nested objects gracefully' do
      hash_without_nested = trade_hash.dup
      hash_without_nested.delete(:order)
      hash_without_nested.delete(:progress)

      trade = described_class.from_h(hash_without_nested)

      expect(mock_order_manager).not_to have_received(:from_h)
      expect(mock_progress).not_to have_received(:from_h)
    end

    it 'parses timestamp correctly' do
      trade = described_class.from_h(trade_hash)

      expect(trade.timestamp).to eq(Time.parse('2025-06-20T10:30:00Z'))
    end

    it 'handles nil timestamp gracefully' do
      hash_without_timestamp = trade_hash.dup
      hash_without_timestamp.delete(:timestamp)

      trade = described_class.from_h(hash_without_timestamp)

      expect(trade.timestamp).to be_nil
    end
  end

  describe 'round-trip serialization' do
    let(:mock_strategy_with_full_data) do
      double('Strategy',
        type: 'ironcondor',
        to_h: {
          type: 'ironcondor',
          underlying_symbol: 'QQQ',
          quantity: 3,
          credit: 2.50,
          put_spread: {
            type: 'putspread',
            short_leg: { symbol: 'QQQ_PUT_SHORT' },
            long_leg: { symbol: 'QQQ_PUT_LONG' }
          },
          call_spread: {
            type: 'callspread',
            short_leg: { symbol: 'QQQ_CALL_SHORT' },
            long_leg: { symbol: 'QQQ_CALL_LONG' }
          }
        }
      )
    end

    let(:original_trade) do
      described_class.new(
        trade_id: 'round-trip-test',
        strategy: mock_strategy_with_full_data,
        paper_trading: true,
        strategy_type: 'ironcondor',
        underlying_symbol: 'QQQ',
        expiration_date: Date.new(2025, 7, 18),
        short_delta: 0.10,
        max_spread: 20.0,
        min_credit: 200.0,
        quantity: 3,
        profit_thresh: 0.75,
        loss_thresh: -3.0,
        green_delta: 0.20,
        yellow_delta: 0.30,
        strategy_adjuster: mock_strategy_adjuster
      )
    end

    before do
      allow(described_class).to receive(:create_strategy_from_h)
        .with(mock_strategy_with_full_data.to_h)
        .and_return(mock_strategy_with_full_data)
    end

    it 'preserves data through to_h and from_h cycle' do
      # Convert to hash
      hash = original_trade.to_h

      # Convert back to object
      restored_trade = described_class.from_h(hash)

      # Verify core attributes are preserved
      expect(restored_trade.trade_id).to eq(original_trade.trade_id)
      expect(restored_trade.paper_trading).to eq(original_trade.paper_trading)
      expect(restored_trade.current_state).to eq(original_trade.current_state)
      expect(restored_trade.instance_variable_get(:@underlying_symbol)).to eq('QQQ')
      expect(restored_trade.instance_variable_get(:@quantity)).to eq(3)
    end
  end

  describe '#next' do
    let(:trade) do
      described_class.new(
        trade_id: 'test-trade-123',
        strategy: mock_strategy,
        paper_trading: false,
        strategy_type: 'ironcondor',
        underlying_symbol: 'SPY',
        expiration_date: Date.new(2025, 6, 20),
        quantity: 1
      )
    end

    let(:mock_strategy_finder_factory) do
      double('StrategyFinderFactory',
        search: mock_strategy
      )
    end

    before do
      allow(trade).to receive(:strategy_finder_factory).and_return(mock_strategy_finder_factory)
      allow(Time).to receive(:now).and_return(Time.new(2025, 6, 20, 10, 30, 0))
      allow(mock_strategy).to receive(:market_change?).and_return(false)
      allow(mock_strategy).to receive(:check_market).and_return(true)
      allow(mock_order_manager).to receive(:check_order_status).and_return(true)
      allow(mock_order_manager).to receive(:working?).and_return(false)
      allow(mock_order_manager).to receive(:filled?).and_return(false)
      allow(mock_order_manager).to receive(:failed?).and_return(false)
      allow(mock_order_manager).to receive(:stop_working_order).and_return(true)
      allow(mock_order_manager).to receive(:send_preview_order).and_return(true)
      allow(mock_order_manager).to receive(:send_order).and_return(true)
      allow(mock_progress).to receive(:exit?).and_return(false)
      allow(mock_risk_monitor).to receive(:danger?).and_return(false)
    end

    context 'when current_state is NO_TRADE_FOUND' do
      before do
        trade.instance_variable_set(:@current_state, OptionsTrader::Trades::TRADE_STATES[:no_trade_found])
      end

      it 'calls find_strategy' do
        expect(trade).to receive(:find_strategy)
        trade.next
      end

      it 'updates timestamp and logs to journal' do
        allow(trade).to receive(:find_strategy)
        expected_time = Time.new(2025, 6, 20, 10, 30, 0)

        trade.next

        expect(trade.timestamp).to eq(expected_time)
        expect(mock_trade_journal).to have_received(:log).with(trade)
      end
    end

    context 'when current_state is OPEN_ORDER_FAILED' do
      before do
        trade.instance_variable_set(:@current_state, OptionsTrader::Trades::TRADE_STATES[:open_order_failed])
      end

      it 'calls find_strategy' do
        expect(trade).to receive(:find_strategy)
        trade.next
      end
    end

    context 'when current_state is CLOSE_ORDER_FAILED' do
      before do
        trade.instance_variable_set(:@current_state, OptionsTrader::Trades::TRADE_STATES[:close_order_failed])
      end

      it 'calls send_close_order' do
        expect(trade).to receive(:send_close_order)
        trade.next
      end
    end

    context 'when current_state is TRADE_FOUND' do
      before do
        trade.instance_variable_set(:@current_state, OptionsTrader::Trades::TRADE_STATES[:trade_found])
      end

      it 'calls send_open_order' do
        expect(trade).to receive(:send_open_order)
        trade.next
      end
    end

    context 'when current_state is OPEN_ORDER_SENT' do
      before do
        trade.instance_variable_set(:@current_state, OptionsTrader::Trades::TRADE_STATES[:open_order_sent])
      end

      it 'calls check_open_order' do
        expect(trade).to receive(:check_open_order)
        trade.next
      end
    end

    context 'when current_state is CLOSE_ORDER_SENT' do
      before do
        trade.instance_variable_set(:@current_state, OptionsTrader::Trades::TRADE_STATES[:close_order_sent])
      end

      it 'calls check_close_order' do
        expect(trade).to receive(:check_close_order)
        trade.next
      end
    end

    context 'when current_state is ADJUST_OPEN_ORDER_SENT' do
      before do
        trade.instance_variable_set(:@current_state, OptionsTrader::Trades::TRADE_STATES[:adjust_open_order_sent])
      end

      it 'calls check_adjust_open_order' do
        expect(trade).to receive(:check_adjust_open_order)
        trade.next
      end
    end

    context 'when current_state is ADJUST_CLOSE_ORDER_SENT' do
      before do
        trade.instance_variable_set(:@current_state, OptionsTrader::Trades::TRADE_STATES[:adjust_close_order_sent])
      end

      it 'calls check_adjust_close_order' do
        expect(trade).to receive(:check_adjust_close_order)
        trade.next
      end
    end

    context 'when current_state is ADJUST_EXITED' do
      before do
        trade.instance_variable_set(:@current_state, OptionsTrader::Trades::TRADE_STATES[:adjust_exited])
      end

      it 'calls send_adjust_open_order' do
        expect(trade).to receive(:send_adjust_open_order)
        trade.next
      end
    end

    context 'when current_state is TRADE_OPEN' do
      before do
        trade.instance_variable_set(:@current_state, OptionsTrader::Trades::TRADE_STATES[:trade_open])
      end

      it 'calls check_trade_progress_and_risk' do
        expect(trade).to receive(:check_trade_progress_and_risk)
        trade.next
      end
    end

    context 'when current_state is TRADE_ENTERED' do
      before do
        trade.instance_variable_set(:@current_state, OptionsTrader::Trades::TRADE_STATES[:trade_entered])
      end

      it 'calls check_trade_progress_and_risk' do
        expect(trade).to receive(:check_trade_progress_and_risk)
        trade.next
      end
    end

    context 'when current_state is TRADE_OPEN_AT_RISK' do
      before do
        trade.instance_variable_set(:@current_state, OptionsTrader::Trades::TRADE_STATES[:trade_open_at_risk])
      end

      it 'calls check_trade_progress_and_risk' do
        expect(trade).to receive(:check_trade_progress_and_risk)
        trade.next
      end
    end

    context 'when current_state is TRADE_EXITED' do
      before do
        trade.instance_variable_set(:@current_state, OptionsTrader::Trades::TRADE_STATES[:trade_exited])
      end

      it 'does nothing (noop)' do
        # Should not call any methods except for the ensure block
        expect(trade).not_to receive(:find_strategy)
        expect(trade).not_to receive(:send_close_order)
        expect(trade).not_to receive(:check_trade_progress_and_risk)

        trade.next

        # But should still update timestamp and log
        expect(mock_trade_journal).to have_received(:log).with(trade)
      end
    end

    context 'when current_state is unknown' do
      before do
        trade.instance_variable_set(:@current_state, 'UNKNOWN_STATE')
      end

      it 'raises an error' do
        expect { trade.next }.to raise_error("Unknown state: UNKNOWN_STATE")
      end

      it 'still updates timestamp and logs to journal even when error occurs' do
        expected_time = Time.new(2025, 6, 20, 10, 30, 0)

        expect { trade.next }.to raise_error("Unknown state: UNKNOWN_STATE")

        expect(trade.timestamp).to eq(expected_time)
        expect(mock_trade_journal).to have_received(:log).with(trade)
      end
    end

    context 'ensure block behavior' do
      before do
        trade.instance_variable_set(:@current_state, OptionsTrader::Trades::TRADE_STATES[:trade_exited])
      end

      it 'always updates timestamp to current UTC time' do
        expected_time = Time.new(2025, 6, 20, 10, 30, 0)
        allow(Time).to receive(:now).and_return(double(utc: expected_time))

        trade.next

        expect(trade.timestamp).to eq(expected_time)
      end

      it 'always logs to journal' do
        trade.next

        expect(mock_trade_journal).to have_received(:log).with(trade)
      end
    end
  end

  describe '#next integration tests' do
    let(:trade) do
      described_class.new(
        trade_id: 'integration-test-123',
        strategy: mock_strategy,
        paper_trading: true,
        strategy_type: 'ironcondor',
        underlying_symbol: 'SPY',
        expiration_date: Date.new(2025, 6, 20),
        quantity: 1
      )
    end

    let(:mock_strategy_finder_factory) do
      double('StrategyFinderFactory')
    end

    before do
      allow(trade).to receive(:strategy_finder_factory).and_return(mock_strategy_finder_factory)
      allow(Time).to receive(:now).and_return(Time.new(2025, 6, 20, 10, 30, 0))
      allow(mock_strategy).to receive(:market_change?).and_return(false)
      allow(mock_strategy).to receive(:check_market).and_return(true)
      allow(mock_order_manager).to receive(:check_order_status).and_return(true)
      allow(mock_order_manager).to receive(:working?).and_return(false)
      allow(mock_order_manager).to receive(:filled?).and_return(false)
      allow(mock_order_manager).to receive(:failed?).and_return(false)
      allow(mock_order_manager).to receive(:stop_working_order).and_return(true)
      allow(mock_order_manager).to receive(:send_preview_order).and_return(true)
      allow(mock_order_manager).to receive(:send_order).and_return(true)
      allow(mock_progress).to receive(:exit?).and_return(false)
      allow(mock_risk_monitor).to receive(:danger?).and_return(false)
    end

    context 'successful trade flow' do
      it 'transitions from NO_TRADE_FOUND to TRADE_FOUND when strategy is found' do
        allow(mock_strategy_finder_factory).to receive(:search).and_return(mock_strategy)

        trade.instance_variable_set(:@current_state, OptionsTrader::Trades::TRADE_STATES[:no_trade_found])

        trade.next

        expect(trade.current_state).to eq(OptionsTrader::Trades::TRADE_STATES[:trade_found])
        expect(trade.find_trade_attempts).to eq(0)
      end

      it 'transitions from NO_TRADE_FOUND to NO_TRADE_FOUND when no strategy is found' do
        allow(mock_strategy_finder_factory).to receive(:search).and_return(nil)

        trade.instance_variable_set(:@current_state, OptionsTrader::Trades::TRADE_STATES[:no_trade_found])
        initial_attempts = trade.find_trade_attempts

        trade.next

        expect(trade.current_state).to eq(OptionsTrader::Trades::TRADE_STATES[:no_trade_found])
        expect(trade.find_trade_attempts).to eq(initial_attempts + 1)
      end

      it 'transitions from TRADE_FOUND to OPEN_ORDER_SENT when sending open order' do
        trade.instance_variable_set(:@current_state, OptionsTrader::Trades::TRADE_STATES[:trade_found])

        trade.next

        expect(trade.current_state).to eq(OptionsTrader::Trades::TRADE_STATES[:open_order_sent])
        expect(mock_order_manager).to have_received(:send_preview_order).with(mock_strategy, order_instruction: :open)
      end

      it 'transitions from OPEN_ORDER_SENT to TRADE_ENTERED when order is filled in paper trading' do
        allow(mock_order_manager).to receive(:filled?).and_return(true)
        trade.instance_variable_set(:@current_state, OptionsTrader::Trades::TRADE_STATES[:open_order_sent])

        trade.next

        expect(trade.current_state).to eq(OptionsTrader::Trades::TRADE_STATES[:trade_entered])
        expect(trade.working_cnt).to eq(1)
      end

      it 'transitions from TRADE_ENTERED to TRADE_OPEN when no exit conditions are met' do
        trade.instance_variable_set(:@current_state, OptionsTrader::Trades::TRADE_STATES[:trade_entered])

        trade.next

        expect(trade.current_state).to eq(OptionsTrader::Trades::TRADE_STATES[:trade_open])
        expect(trade.working_cnt).to eq(0)
      end

      it 'transitions from TRADE_OPEN to CLOSE_ORDER_SENT when exit conditions are met' do
        allow(mock_progress).to receive(:exit?).and_return(true)
        trade.instance_variable_set(:@current_state, OptionsTrader::Trades::TRADE_STATES[:trade_open])

        trade.next

        expect(trade.current_state).to eq(OptionsTrader::Trades::TRADE_STATES[:close_order_sent])
        expect(mock_order_manager).to have_received(:send_preview_order).with(mock_strategy, order_instruction: :exit)
      end

      it 'transitions from CLOSE_ORDER_SENT to TRADE_EXITED when close order is filled' do
        allow(mock_order_manager).to receive(:filled?).and_return(true)
        trade.instance_variable_set(:@current_state, OptionsTrader::Trades::TRADE_STATES[:close_order_sent])

        trade.next

        expect(trade.current_state).to eq(OptionsTrader::Trades::TRADE_STATES[:trade_exited])
        expect(trade.working_cnt).to eq(1)
      end
    end

    context 'error handling' do
      it 'transitions to SEND_ORDER_ERROR when send_open_order raises an exception' do
        allow(mock_order_manager).to receive(:send_preview_order).and_raise(StandardError.new('Connection failed'))
        trade.instance_variable_set(:@current_state, OptionsTrader::Trades::TRADE_STATES[:trade_found])

        expect { trade.next }.to output(/Error opening trade/).to_stdout

        expect(trade.current_state).to eq(OptionsTrader::Trades::TRADE_STATES[:send_order_error])
      end

      it 'transitions to SEND_ORDER_ERROR when send_close_order raises an exception' do
        allow(mock_order_manager).to receive(:send_preview_order).and_raise(StandardError.new('Connection failed'))
        allow(mock_progress).to receive(:exit?).and_return(true)
        trade.instance_variable_set(:@current_state, OptionsTrader::Trades::TRADE_STATES[:trade_open])

        expect { trade.next }.to output(/Error exiting trade/).to_stdout

        expect(trade.current_state).to eq(OptionsTrader::Trades::TRADE_STATES[:send_order_error])
      end
    end

    context 'risk management and adjustments' do
      let(:trade_with_adjuster) do
        described_class.new(
          trade_id: 'risk-test-123',
          strategy: mock_strategy,
          paper_trading: true,
          strategy_type: 'ironcondor',
          underlying_symbol: 'SPY',
          expiration_date: Date.new(2025, 6, 20),
          quantity: 1,
          strategy_adjuster: mock_strategy_adjuster
        )
      end

      before do
        allow(trade_with_adjuster).to receive(:strategy_finder_factory).and_return(mock_strategy_finder_factory)
        allow(Time).to receive(:now).and_return(Time.new(2025, 6, 20, 10, 30, 0))
        allow(mock_strategy).to receive(:market_change?).and_return(false)
        allow(mock_strategy).to receive(:check_market).and_return(true)
        allow(mock_order_manager).to receive(:check_order_status).and_return(true)
        allow(mock_order_manager).to receive(:working?).and_return(false)
        allow(mock_order_manager).to receive(:filled?).and_return(false)
        allow(mock_order_manager).to receive(:failed?).and_return(false)
        allow(mock_order_manager).to receive(:stop_working_order).and_return(true)
        allow(mock_order_manager).to receive(:send_preview_order).and_return(true)
        allow(mock_order_manager).to receive(:send_order).and_return(true)
        allow(mock_progress).to receive(:exit?).and_return(false)
        allow(mock_risk_monitor).to receive(:danger?).and_return(true)
        allow(mock_strategy_adjuster).to receive(:find_new_strategy).and_return(double('Adjustment', new_strategy: mock_strategy))
      end

      it 'transitions to ADJUST_CLOSE_ORDER_SENT when risk is detected and adjustment is available' do
        trade_with_adjuster.instance_variable_set(:@current_state, OptionsTrader::Trades::TRADE_STATES[:trade_open])

        trade_with_adjuster.next

        expect(trade_with_adjuster.current_state).to eq(OptionsTrader::Trades::TRADE_STATES[:adjust_close_order_sent])
        expect(mock_strategy_adjuster).to have_received(:find_new_strategy).with(mock_strategy)
      end

      it 'transitions to TRADE_OPEN_AT_RISK when risk is detected but no adjustment is available' do
        allow(mock_strategy_adjuster).to receive(:find_new_strategy).and_return(nil)
        trade_with_adjuster.instance_variable_set(:@current_state, OptionsTrader::Trades::TRADE_STATES[:trade_open])

        trade_with_adjuster.next

        expect(trade_with_adjuster.current_state).to eq(OptionsTrader::Trades::TRADE_STATES[:trade_open_at_risk])
      end
    end
  end
end
