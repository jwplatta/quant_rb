require 'spec_helper'
require 'tempfile'
require 'fileutils'

RSpec.describe Platypi::Automation::Bot do
  let(:config) do
    {
      strategy_type: :ironcondor,
      underlying_symbol: '$SPX',
      option_root: 'SPXW',
      settlement_type: 'P',
      days_to_expiration: 1,
      min_credit: 1.00,
      min_open_interest: 25,
      max_delta: 0.15,
      profit_target_threshold: 0.7,
      max_loss_threshold: -2.5,
      sleep_interval: 0.1
    }
  end

  let(:bot) do
    described_class.new(
      name: 'Test Bot',
      mode: :paper,
      account: '123456789',
      config: config
    )
  end

  let(:mock_trade) do
    double('Trade',
      trade_id: 'test_trade_123',
      next: nil,
      exited?: false
    )
  end

  before do
    # Clean up any existing trade files
    Dir.glob("CURRENT_*_TRADE.txt").each { |f| File.delete(f) }
  end

  after do
    # Clean up test files
    Dir.glob("CURRENT_*_TRADE.txt").each { |f| File.delete(f) }
  end

  describe '#initialize' do
    it 'sets basic attributes correctly' do
      expect(bot.name).to eq('Test Bot')
      expect(bot.mode).to eq(:paper)
      expect(bot.account).to eq('123456789')
      expect(bot.running).to be false
      expect(bot.current_trade).to be nil
    end

    it 'sets default config values' do
      expect(bot.config[:sleep_interval]).to eq(0.1)
    end
  end

  describe '#sanitized_bot_name' do
    it 'converts name to uppercase and replaces special characters' do
      bot_with_special_name = described_class.new(
        name: 'SPX Weekly Iron-Condor Bot!',
        mode: :paper,
        config: config
      )

      expect(bot_with_special_name.send(:sanitized_bot_name)).to eq('SPX_WEEKLY_IRON_CONDOR_BOT_')
    end
  end

  describe '#current_trade_file_path' do
    it 'generates correct file path' do
      expected_path = File.join(Dir.pwd, 'CURRENT_TEST_BOT_TRADE.txt')
      expect(bot.send(:current_trade_file_path)).to eq(expected_path)
    end
  end

  describe '#should_enter_trade?' do
    it 'returns true for immediately timing' do
      bot.config[:enter_timing] = :immediately
      expect(bot.send(:should_enter_trade?)).to be true
    end

    it 'returns true for default case' do
      bot.config[:enter_timing] = :unknown
      expect(bot.send(:should_enter_trade?)).to be true
    end
  end

  describe '#calculate_expiration_date' do
    it 'calculates expiration date for iron condor strategy' do
      bot.config[:strategy_type] = :ironcondor
      bot.config[:option_root] = 'SPXW'
      bot.config[:days_to_expiration] = 1

      expiration = bot.send(:calculate_expiration_date)
      expect(expiration).to be_a(Date)
      expect(expiration.wday).to eq(5) # Friday
    end

    it 'uses default of 1 day if not specified' do
      bot.config.delete(:days_to_expiration)
      bot.config[:strategy_type] = :other

      expected_date = Date.today + 1
      expiration = bot.send(:calculate_expiration_date)
      expect(expiration).to eq(expected_date)
    end
  end

  describe '#write_current_trade_file' do
    it 'writes trade ID to file' do
      bot.instance_variable_set(:@current_trade, mock_trade)
      allow(bot).to receive(:puts) # Suppress output

      bot.send(:write_current_trade_file)

      expect(File.exist?(bot.send(:current_trade_file_path))).to be true
      expect(File.read(bot.send(:current_trade_file_path))).to eq('test_trade_123')
    end
  end

  describe '#clear_current_trade_file' do
    it 'deletes the trade file if it exists' do
      # Create a file first
      File.write(bot.send(:current_trade_file_path), 'test_trade')
      expect(File.exist?(bot.send(:current_trade_file_path))).to be true

      allow(bot).to receive(:puts) # Suppress output
      bot.send(:clear_current_trade_file)

      expect(File.exist?(bot.send(:current_trade_file_path))).to be false
    end
  end

  describe '#stop' do
    it 'sets running to false' do
      bot.instance_variable_set(:@running, true)
      allow(bot).to receive(:puts) # Suppress output

      bot.stop

      expect(bot.running).to be false
    end
  end
end
