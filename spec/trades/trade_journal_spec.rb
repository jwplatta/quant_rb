# frozen_string_literal: true

require_relative '../spec_helper'
require 'fileutils'
require 'tmpdir'

RSpec.describe Platypi::Trades::TradeJournal do
  let(:trade_id) { 'test-trade-123' }
  let(:temp_dir) { Dir.mktmpdir }
  let(:journal) { described_class.new(trade_id) }

  before do
    # Set up temporary directory for testing
    allow(ENV).to receive(:fetch).with('TRADE_JOURNAL_PATH', anything).and_return(temp_dir)
  end

  after do
    # Clean up temporary directory
    FileUtils.rm_rf(temp_dir)
  end

  describe '.base_path' do
    context 'when TRADE_JOURNAL_PATH is set' do
      it 'returns the environment variable value' do
        allow(ENV).to receive(:fetch).with('TRADE_JOURNAL_PATH', anything).and_return('/custom/path')

        expect(described_class.base_path).to eq('/custom/path')
      end
    end

    context 'when TRADE_JOURNAL_PATH is not set' do
      it 'returns the default path' do
        # Override the stub to simulate no environment variable
        allow(ENV).to receive(:fetch).with('TRADE_JOURNAL_PATH', anything).and_call_original
        allow(ENV).to receive(:[]).with('TRADE_JOURNAL_PATH').and_return(nil)
        allow(ENV).to receive(:fetch).with('TRADE_JOURNAL_PATH', anything) do |key, default|
          default
        end
        expected_path = File.join(Dir.home, '.platypi', 'trade_journal')

        expect(described_class.base_path).to eq(expected_path)
      end
    end
  end

  describe '.ensure_directory_exists' do
    it 'creates the directory if it does not exist' do
      custom_path = File.join(temp_dir, 'custom_journal')
      allow(ENV).to receive(:fetch).with('TRADE_JOURNAL_PATH', anything).and_return(custom_path)

      expect(Dir.exist?(custom_path)).to be false
      described_class.ensure_directory_exists
      expect(Dir.exist?(custom_path)).to be true
    end

    it 'does nothing if the directory already exists' do
      expect(Dir.exist?(temp_dir)).to be true
      expect { described_class.ensure_directory_exists }.not_to raise_error
    end
  end

  describe '#initialize' do
    it 'sets the trade_id' do
      expect(journal.trade_id).to eq(trade_id)
    end

    it 'ensures the directory exists' do
      expect(described_class).to receive(:ensure_directory_exists)
      described_class.new(trade_id)
    end

    it 'creates the file if it does not exist' do
      new_journal = described_class.new('new-trade-456')
      expect(File.exist?(new_journal.file_path)).to be true
    end
  end

  describe '#file_path' do
    it 'returns the correct file path' do
      expected_path = File.join(temp_dir, "trade_#{trade_id}.jsonl")
      expect(journal.file_path).to eq(expected_path)
    end
  end

  describe '#log' do
    let(:mock_trade) do
      double('Trade',
        to_json: '{"trade_id":"test-123","state":"TRADE_ENTERED","timestamp":"2025-07-06T10:00:00Z"}')
    end

    it 'writes trade data to the file' do
      journal.log(mock_trade)

      content = File.read(journal.file_path)
      expect(content).to include(mock_trade.to_json)
    end

    it 'appends to existing file content' do
      first_trade = double('Trade', to_json: '{"trade_id":"test-123","state":"TRADE_FOUND"}')
      second_trade = double('Trade', to_json: '{"trade_id":"test-123","state":"TRADE_ENTERED"}')

      journal.log(first_trade)
      journal.log(second_trade)

      content = File.read(journal.file_path)
      expect(content).to include(first_trade.to_json)
      expect(content).to include(second_trade.to_json)
    end
  end

  describe '#trade_history' do
    let(:mock_trade_1) do
      double('Trade',
        current_state: 'TRADE_FOUND',
        timestamp: Time.parse('2025-07-06T10:00:00Z'))
    end

    let(:mock_trade_2) do
      double('Trade',
        current_state: 'TRADE_ENTERED',
        timestamp: Time.parse('2025-07-06T11:00:00Z'))
    end

    it 'parses trade history from file' do
      # Write test data to file before creating journal
      File.write(File.join(temp_dir, "trade_#{trade_id}.jsonl"),
        '{"trade_id":"test-123","state":"TRADE_FOUND","timestamp":"2025-07-06T10:00:00Z"}' + "\n" +
        '{"trade_id":"test-123","state":"TRADE_ENTERED","timestamp":"2025-07-06T11:00:00Z"}' + "\n")

      expect(Platypi::Trades::Trade).to receive(:from_json).twice.and_return(mock_trade_1, mock_trade_2)

      # Create journal after writing file so it loads the data
      new_journal = described_class.new(trade_id)
      history = new_journal.trade_history
      expect(history).to contain_exactly(mock_trade_1, mock_trade_2)
    end

    it 'handles empty lines' do
      # Write test data to file before creating journal
      File.write(File.join(temp_dir, "trade_#{trade_id}.jsonl"),
        '{"trade_id":"test-123","state":"TRADE_FOUND"}' + "\n" +
        '' + "\n" +
        '{"trade_id":"test-123","state":"TRADE_ENTERED"}' + "\n")

      expect(Platypi::Trades::Trade).to receive(:from_json).twice.and_return(mock_trade_1, mock_trade_2)

      # Create journal after writing file so it loads the data
      new_journal = described_class.new(trade_id)
      history = new_journal.trade_history
      expect(history).to contain_exactly(mock_trade_1, mock_trade_2)
    end

    it 'handles JSON parsing errors gracefully' do
      # Write test data to file before creating journal
      File.write(File.join(temp_dir, "trade_#{trade_id}.jsonl"),
        '{"trade_id":"test-123","state":"TRADE_FOUND"}' + "\n" +
        'invalid json' + "\n" +
        '{"trade_id":"test-123","state":"TRADE_ENTERED"}' + "\n")

      expect(Platypi::Trades::Trade).to receive(:from_json).with('{"trade_id":"test-123","state":"TRADE_FOUND"}').and_return(mock_trade_1)
      expect(Platypi::Trades::Trade).to receive(:from_json).with('invalid json').and_raise(JSON::ParserError.new('invalid'))
      expect(Platypi::Trades::Trade).to receive(:from_json).with('{"trade_id":"test-123","state":"TRADE_ENTERED"}').and_return(mock_trade_2)

      # Create journal after writing file so it loads the data
      new_journal = nil
      expect { new_journal = described_class.new(trade_id) }.to output(/Error parsing trade history line/).to_stdout
      history = new_journal.trade_history
      expect(history).to contain_exactly(mock_trade_1, mock_trade_2)
    end
  end

  describe '#last_event' do
    let(:early_trade) do
      double('Trade', timestamp: Time.parse('2025-07-06T10:00:00Z'))
    end

    let(:late_trade) do
      double('Trade', timestamp: Time.parse('2025-07-06T11:00:00Z'))
    end

    it 'returns the trade with the earliest timestamp' do
      allow(journal).to receive(:trade_history).and_return([late_trade, early_trade])

      expect(journal.last_event).to eq(early_trade)
    end

    it 'caches the result' do
      allow(journal).to receive(:trade_history).and_return([late_trade, early_trade])

      result1 = journal.last_event
      result2 = journal.last_event

      expect(result1).to eq(result2)
    end
  end

  describe '#trade_entered_event' do
    let(:trade_found) do
      double('Trade', current_state: 'TRADE_FOUND')
    end

    let(:trade_entered) do
      double('Trade', current_state: 'TRADE_ENTERED')
    end

    it 'returns the first trade with TRADE_ENTERED state' do
      allow(journal).to receive(:trade_history).and_return([trade_found, trade_entered])

      expect(journal.trade_entered_event).to eq(trade_entered)
    end

    it 'returns nil when no trade entered' do
      allow(journal).to receive(:trade_history).and_return([trade_found])

      expect(journal.trade_entered_event).to be_nil
    end
  end

  describe '#trade_exited_event' do
    let(:trade_entered) do
      double('Trade', current_state: 'TRADE_ENTERED')
    end

    let(:trade_exited) do
      double('Trade', current_state: 'TRADE_EXITED')
    end

    it 'returns the first trade with TRADE_EXITED state' do
      allow(journal).to receive(:trade_history).and_return([trade_entered, trade_exited])

      expect(journal.trade_exited_event).to eq(trade_exited)
    end

    it 'returns nil when no trade exited' do
      allow(journal).to receive(:trade_history).and_return([trade_entered])

      expect(journal.trade_exited_event).to be_nil
    end
  end

  describe '#trade_adjustment_events' do
    let(:trade_entered) do
      double('Trade', current_state: 'TRADE_ENTERED')
    end

    let(:adjust_exited) do
      double('Trade', current_state: 'ADJUST_EXITED')
    end

    let(:adjust_entered) do
      double('Trade', current_state: 'ADJUST_ENTERED')
    end

    it 'returns only trades with adjustment states' do
      allow(journal).to receive(:trade_history).and_return([trade_entered, adjust_exited, adjust_entered])

      expect(journal.trade_adjustment_events).to contain_exactly(adjust_exited, adjust_entered)
    end

    it 'returns empty array when no adjustments' do
      allow(journal).to receive(:trade_history).and_return([trade_entered])

      expect(journal.trade_adjustment_events).to be_empty
    end
  end

  describe '.read_or_init' do
    it 'returns a new TradeJournal instance' do
      result = described_class.read_or_init('test-trade-456')

      expect(result).to be_a(described_class)
      expect(result.trade_id).to eq('test-trade-456')
    end
  end

  describe '.trade_open?' do
    context 'when trade has entered but not exited' do
      it 'returns true' do
        trade_id = 'open-trade-123'
        journal = described_class.new(trade_id)

        entered_trade = double('Trade', current_state: 'TRADE_ENTERED')
        allow(journal).to receive(:trade_entered_event).and_return(entered_trade)
        allow(journal).to receive(:trade_exited_event).and_return(nil)
        allow(described_class).to receive(:new).with(trade_id).and_return(journal)

        expect(described_class.trade_open?(trade_id)).to be true
      end
    end

    context 'when trade has not entered' do
      it 'returns false' do
        trade_id = 'no-entry-trade-123'
        journal = described_class.new(trade_id)

        allow(journal).to receive(:trade_entered_event).and_return(nil)
        allow(journal).to receive(:trade_exited_event).and_return(nil)
        allow(described_class).to receive(:new).with(trade_id).and_return(journal)

        expect(described_class.trade_open?(trade_id)).to be false
      end
    end

    context 'when trade has entered and exited' do
      it 'returns false' do
        trade_id = 'closed-trade-123'
        journal = described_class.new(trade_id)

        entered_trade = double('Trade', current_state: 'TRADE_ENTERED')
        exited_trade = double('Trade', current_state: 'TRADE_EXITED')
        allow(journal).to receive(:trade_entered_event).and_return(entered_trade)
        allow(journal).to receive(:trade_exited_event).and_return(exited_trade)
        allow(described_class).to receive(:new).with(trade_id).and_return(journal)

        expect(described_class.trade_open?(trade_id)).to be false
      end
    end

    context 'when file does not exist' do
      it 'returns false' do
        trade_id = 'nonexistent-trade-123'
        journal = described_class.new(trade_id)

        allow(journal).to receive(:trade_entered_event).and_raise(Errno::ENOENT)
        allow(described_class).to receive(:new).with(trade_id).and_return(journal)

        expect(described_class.trade_open?(trade_id)).to be false
      end
    end
  end

  describe 'file operations' do
    it 'handles non-existent files gracefully' do
      non_existent_journal = described_class.new('non-existent-trade')
      FileUtils.rm_f(non_existent_journal.file_path)

      # Since the initialize method creates the file, accessing trade_history should work
      expect(non_existent_journal.trade_history).to be_empty
    end
  end

  describe 'integration with actual file system' do
    let(:integration_journal) { described_class.new('integration-test') }
    let(:mock_trade) do
      double('Trade',
        to_json: '{"trade_id":"integration-test","state":"TRADE_ENTERED","timestamp":"2025-07-06T10:00:00Z"}')
    end

    it 'can write and read trade data' do
      integration_journal.log(mock_trade)

      content = File.read(integration_journal.file_path)
      expect(content.strip).to eq(mock_trade.to_json)
    end
  end
end
