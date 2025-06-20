# frozen_string_literal: true

require_relative '../spec_helper'
require 'fileutils'
require 'tmpdir'

RSpec.describe Platypi::TradeJournal do
  let(:test_base_path) { Dir.mktmpdir('trade_journal_test') }
  let(:trade_id) { 'test-trade-123' }
  let(:journal) { described_class.new(trade_id) }

  # Mock trade object for testing
  let(:mock_trade) do
    double('Trade',
      trade_id: trade_id,
      status: 'OPEN',
      to_json: '{"trade_id":"test-trade-123","status":"OPEN","timestamp":"2025-06-20T10:00:00Z"}'
    )
  end

  let(:closed_trade) do
    double('Trade',
      trade_id: trade_id,
      status: 'EXIT',
      to_json: '{"trade_id":"test-trade-123","status":"EXIT","timestamp":"2025-06-20T11:00:00Z"}'
    )
  end

  before do
    # Override the base path for testing and clear memoized values
    described_class.instance_variable_set(:@base_path, test_base_path)
    described_class.instance_variable_set(:@open_trades_path, nil)
    described_class.instance_variable_set(:@closed_trades_path, nil)

    # Ensure directories exist for each test
    described_class.ensure_directories_exist
  end

  after do
    # Clean up test directory and reset class variables
    FileUtils.rm_rf(test_base_path) if Dir.exist?(test_base_path)
    described_class.instance_variable_set(:@base_path, nil)
    described_class.instance_variable_set(:@open_trades_path, nil)
    described_class.instance_variable_set(:@closed_trades_path, nil)
  end

  describe '.base_path' do
    it 'uses ENV variable if set' do
      # Reset the memoized value first
      described_class.instance_variable_set(:@base_path, nil)
      allow(ENV).to receive(:fetch).with('TRADE_JOURNAL_PATH', anything).and_return('/custom/path')
      expect(described_class.base_path).to eq('/custom/path')
    end

    it 'uses default path if ENV not set' do
      described_class.instance_variable_set(:@base_path, nil)
      ENV['TRADE_JOURNAL_PATH'] = nil
      expected_path = File.join(Dir.home, '.platypi', 'trade_journal')
      expect(described_class.base_path).to eq(expected_path)
    end
  end

  describe '.ensure_directories_exist' do
    it 'creates open and closed directories' do
      # Clear directories first
      FileUtils.rm_rf(test_base_path)
      described_class.instance_variable_set(:@base_path, test_base_path)
      described_class.instance_variable_set(:@open_trades_path, nil)
      described_class.instance_variable_set(:@closed_trades_path, nil)

      described_class.ensure_directories_exist

      expect(Dir.exist?(described_class.open_trades_path)).to be true
      expect(Dir.exist?(described_class.closed_trades_path)).to be true
    end
  end

  describe '#initialize' do
    it 'sets trade_id and ensures directories exist' do
      expect(journal.trade_id).to eq(trade_id)
      expect(Dir.exist?(described_class.open_trades_path)).to be true
      expect(Dir.exist?(described_class.closed_trades_path)).to be true
    end
  end

  describe '#save_trade' do
    context 'with an open trade' do
      it 'saves trade to open folder' do
        journal.save_trade(mock_trade)

        file_path = File.join(described_class.open_trades_path, "#{trade_id}.json")
        expect(File.exist?(file_path)).to be true

        content = File.read(file_path)
        expect(content.strip).to eq(mock_trade.to_json)
      end

      it 'appends multiple states to the same file' do
        journal.save_trade(mock_trade)
        journal.save_trade(mock_trade)

        file_path = File.join(described_class.open_trades_path, "#{trade_id}.json")
        lines = File.readlines(file_path)
        expect(lines.length).to eq(2)
        expect(lines.all? { |line| line.strip == mock_trade.to_json }).to be true
      end
    end

    context 'with a closed trade' do
      it 'moves trade file from open to closed folder' do
        # First save an open trade
        journal.save_trade(mock_trade)
        open_file = File.join(described_class.open_trades_path, "#{trade_id}.json")
        expect(File.exist?(open_file)).to be true

        # Then save a closed trade
        journal.save_trade(closed_trade)
        closed_file = File.join(described_class.closed_trades_path, "#{trade_id}.json")

        expect(File.exist?(open_file)).to be false
        expect(File.exist?(closed_file)).to be true

        # Should contain both states
        lines = File.readlines(closed_file)
        expect(lines.length).to eq(2)
      end
    end
  end

  describe '#current_file_path' do
    context 'when trade file exists in open folder' do
      it 'returns open folder path' do
        File.write(File.join(described_class.open_trades_path, "#{trade_id}.json"), mock_trade.to_json)

        expected_path = File.join(described_class.open_trades_path, "#{trade_id}.json")
        expect(journal.current_file_path).to eq(expected_path)
      end
    end

    context 'when trade file exists in closed folder' do
      it 'returns closed folder path' do
        File.write(File.join(described_class.closed_trades_path, "#{trade_id}.json"), closed_trade.to_json)

        expected_path = File.join(described_class.closed_trades_path, "#{trade_id}.json")
        expect(journal.current_file_path).to eq(expected_path)
      end
    end

    context 'when trade file does not exist' do
      it 'returns default open folder path' do
        expected_path = File.join(described_class.open_trades_path, "#{trade_id}.json")
        expect(journal.current_file_path).to eq(expected_path)
      end
    end
  end

  describe '#trade_history' do
    before do
      # Mock the Trade.from_json method
      allow(Platypi::Trades::Trade).to receive(:from_json) do |json_string|
        data = JSON.parse(json_string)
        double('Trade', trade_id: data['trade_id'], status: data['status'])
      end
    end

    it 'returns empty array when file does not exist' do
      expect(journal.trade_history).to eq([])
    end

    it 'returns all trade states from file' do
      journal.save_trade(mock_trade)
      journal.save_trade(closed_trade)

      history = journal.trade_history
      expect(history.length).to eq(2)
      expect(history.first.status).to eq('OPEN')
      expect(history.last.status).to eq('EXIT')
    end

    it 'handles empty lines gracefully' do
      file_path = File.join(described_class.open_trades_path, "#{trade_id}.json")
      File.write(file_path, "#{mock_trade.to_json}\n\n#{closed_trade.to_json}\n")

      history = journal.trade_history
      expect(history.length).to eq(2)
    end
  end

  describe '#delete_trade' do
    before do
      journal.save_trade(mock_trade)
    end

    it 'deletes the trade file' do
      file_path = File.join(described_class.open_trades_path, "#{trade_id}.json")
      expect(File.exist?(file_path)).to be true

      journal.delete_trade
      expect(File.exist?(file_path)).to be false
    end
  end

  describe '.load_open_trades' do
    let(:trade1_id) { 'trade-1' }
    let(:trade2_id) { 'trade-2' }
    let(:closed_trade_id) { 'closed-trade' }

    before do
      # Mock Trade.from_json to return different trades based on content
      allow(Platypi::Trades::Trade).to receive(:from_json) do |json_string|
        data = JSON.parse(json_string)
        double('Trade',
          trade_id: data['trade_id'],
          status: data['status']
        )
      end

      # Create test files
      File.write(
        File.join(described_class.open_trades_path, "#{trade1_id}.json"),
        '{"trade_id":"trade-1","status":"OPEN"}'
      )
      File.write(
        File.join(described_class.open_trades_path, "#{trade2_id}.json"),
        '{"trade_id":"trade-2","status":"PREVIEW_OPEN"}'
      )
      File.write(
        File.join(described_class.open_trades_path, "#{closed_trade_id}.json"),
        '{"trade_id":"closed-trade","status":"EXIT"}'
      )
    end

    it 'returns only trades with open status' do
      trades = described_class.load_open_trades
      expect(trades.length).to eq(2)
      expect(trades.map(&:trade_id)).to contain_exactly(trade1_id, trade2_id)
    end
  end

  describe '.load_closed_trades' do
    let(:closed_trade_id) { 'closed-trade-1' }

    before do
      allow(Platypi::Trades::Trade).to receive(:from_json) do |json_string|
        data = JSON.parse(json_string)
        double('Trade',
          trade_id: data['trade_id'],
          status: data['status']
        )
      end

      File.write(
        File.join(described_class.closed_trades_path, "#{closed_trade_id}.json"),
        '{"trade_id":"closed-trade-1","status":"EXIT"}'
      )
    end

    it 'returns trades from closed folder' do
      trades = described_class.load_closed_trades
      expect(trades.length).to eq(1)
      expect(trades.first.trade_id).to eq(closed_trade_id)
    end
  end

  describe '.load_trade' do
    let(:open_trade_id) { 'open-trade' }
    let(:closed_trade_id) { 'closed-trade' }

    before do
      allow(Platypi::Trades::Trade).to receive(:from_json) do |json_string|
        data = JSON.parse(json_string)
        double('Trade',
          trade_id: data['trade_id'],
          status: data['status']
        )
      end

      File.write(
        File.join(described_class.open_trades_path, "#{open_trade_id}.json"),
        '{"trade_id":"open-trade","status":"OPEN"}'
      )
      File.write(
        File.join(described_class.closed_trades_path, "#{closed_trade_id}.json"),
        '{"trade_id":"closed-trade","status":"EXIT"}'
      )
    end

    it 'finds trade in open folder' do
      trade = described_class.load_trade(open_trade_id)
      expect(trade).not_to be_nil
      expect(trade.trade_id).to eq(open_trade_id)
    end

    it 'finds trade in closed folder' do
      trade = described_class.load_trade(closed_trade_id)
      expect(trade).not_to be_nil
      expect(trade.trade_id).to eq(closed_trade_id)
    end

    it 'returns nil for non-existent trade' do
      trade = described_class.load_trade('non-existent')
      expect(trade).to be_nil
    end
  end

  describe '.trade_open?' do
    let(:open_trade_id) { 'open-trade' }

    before do
      allow(Platypi::Trades::Trade).to receive(:from_json) do |json_string|
        data = JSON.parse(json_string)
        double('Trade',
          trade_id: data['trade_id'],
          status: data['status']
        )
      end
    end

    it 'returns true for open trade' do
      File.write(
        File.join(described_class.open_trades_path, "#{open_trade_id}.json"),
        '{"trade_id":"open-trade","status":"OPEN"}'
      )

      expect(described_class.trade_open?(open_trade_id)).to be true
    end

    it 'returns false for non-existent trade' do
      expect(described_class.trade_open?('non-existent')).to be false
    end

    it 'returns false for closed trade in open folder' do
      File.write(
        File.join(described_class.open_trades_path, "#{open_trade_id}.json"),
        '{"trade_id":"open-trade","status":"EXIT"}'
      )

      expect(described_class.trade_open?(open_trade_id)).to be false
    end
  end

  describe '.open_trade_count' do
    it 'returns count of files in open trades folder' do
      expect(described_class.open_trade_count).to eq(0)

      File.write(File.join(described_class.open_trades_path, 'trade1.json'), '{}')
      File.write(File.join(described_class.open_trades_path, 'trade2.json'), '{}')

      expect(described_class.open_trade_count).to eq(2)
    end
  end

  describe 'thread safety' do
    it 'uses mutex for file operations' do
      mutex = described_class.mutex
      expect(mutex).to receive(:synchronize).at_least(:once).and_call_original

      journal.save_trade(mock_trade)
    end
  end

  describe '#open_state' do
    let(:mock_open_trade) do
      double('Trade',
        trade_id: trade_id,
        status: 'OPEN',
        order_price: 1.50,
        order_fees: 1.14,
        order_commission: 1.30,
        to_json: '{"trade_id":"test-trade-123","status":"OPEN","order_price":1.50}'
      )
    end

    let(:mock_preview_open_trade) do
      double('Trade',
        trade_id: trade_id,
        status: 'PREVIEW_OPEN',
        order_price: 1.25,
        order_fees: 1.14,
        order_commission: 1.30,
        to_json: '{"trade_id":"test-trade-123","status":"PREVIEW_OPEN","order_price":1.25}'
      )
    end

    let(:mock_exit_trade) do
      double('Trade',
        trade_id: trade_id,
        status: 'EXIT',
        order_price: 0.75,
        order_fees: 1.14,
        order_commission: 1.30,
        to_json: '{"trade_id":"test-trade-123","status":"EXIT","order_price":0.75}'
      )
    end

    before do
      allow(Platypi::Trades::Trade).to receive(:from_json) do |json_string|
        data = JSON.parse(json_string)
        case data['status']
        when 'OPEN'
          mock_open_trade
        when 'PREVIEW_OPEN'
          mock_preview_open_trade
        when 'EXIT'
          mock_exit_trade
        end
      end
    end

    context 'when trade has OPEN state in history' do
      before do
        journal.save_trade(mock_open_trade)
        journal.save_trade(mock_exit_trade)
      end

      it 'returns the trade state with OPEN status' do
        open_state = journal.open_state
        expect(open_state).to eq(mock_open_trade)
        expect(open_state.status).to eq('OPEN')
        expect(open_state.order_price).to eq(1.50)
      end
    end

    context 'when trade has PREVIEW_OPEN state in history' do
      before do
        journal.save_trade(mock_preview_open_trade)
        journal.save_trade(mock_exit_trade)
      end

      it 'returns the trade state with PREVIEW_OPEN status' do
        open_state = journal.open_state
        expect(open_state).to eq(mock_preview_open_trade)
        expect(open_state.status).to eq('PREVIEW_OPEN')
        expect(open_state.order_price).to eq(1.25)
      end
    end

    context 'when trade has no open states in history' do
      before do
        journal.save_trade(mock_exit_trade)
      end

      it 'returns nil' do
        expect(journal.open_state).to be_nil
      end
    end

    context 'when trade history is empty' do
      it 'returns nil' do
        expect(journal.open_state).to be_nil
      end
    end

    context 'when trade has both OPEN and PREVIEW_OPEN states' do
      before do
        journal.save_trade(mock_preview_open_trade)
        journal.save_trade(mock_open_trade)
        journal.save_trade(mock_exit_trade)
      end

      it 'returns the first open state found (PREVIEW_OPEN in this case)' do
        open_state = journal.open_state
        expect(open_state).to eq(mock_preview_open_trade)
        expect(open_state.status).to eq('PREVIEW_OPEN')
      end
    end
  end
end