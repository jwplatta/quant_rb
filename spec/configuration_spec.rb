# frozen_string_literal: true

RSpec.describe OptionsTrader::Configuration do
  let(:config) { described_class.new }

  before do
    OptionsTrader.instance_variable_set(:@configuration, nil)
  end

  describe '#add_account' do
    it 'adds a single account' do
      config.add_account('main', '12345678')
      expect(config.account_number('main')).to eq('12345678')
    end

    it 'converts name and number to strings' do
      config.add_account(:trading, 87654321)
      expect(config.account_number('trading')).to eq('87654321')
    end
  end

  describe '#add_accounts' do
    it 'adds multiple accounts at once' do
      accounts = {
        'main' => '12345678',
        'trading' => '87654321',
        'ira' => '11223344'
      }

      config.add_accounts(accounts)

      expect(config.account_number('main')).to eq('12345678')
      expect(config.account_number('trading')).to eq('87654321')
      expect(config.account_number('ira')).to eq('11223344')
    end
  end

  describe '#load_accounts_from_env' do
    before do
      allow(ENV).to receive(:select).and_return({
        'MAIN_ACCOUNT' => '12345678',
        'TRADING_ACCOUNT' => '87654321',
        'IRA_ACCOUNT' => '11223344'
      })
    end

    it 'loads accounts from environment variables' do
      config.load_accounts_from_env

      expect(config.account_number('main')).to eq('12345678')
      expect(config.account_number('trading')).to eq('87654321')
      expect(config.account_number('ira')).to eq('11223344')
    end
  end

  describe '#account_names' do
    it 'returns all account names' do
      config.add_account('main', '12345678')
      config.add_account('trading', '87654321')

      expect(config.account_names).to contain_exactly('main', 'trading')
    end
  end

  describe '#account_exists?' do
    before do
      config.add_account('main', '12345678')
    end

    it 'returns true for existing accounts' do
      expect(config.account_exists?('main')).to be true
    end

    it 'returns false for non-existing accounts' do
      expect(config.account_exists?('unknown')).to be false
    end
  end

  describe '#default_account' do
    it 'can set and get the default account' do
      config.default_account = 'main'
      expect(config.default_account).to eq('main')
    end
  end

  describe '#remove_account' do
    before do
      config.add_account('main', '12345678')
      config.add_account('trading', '87654321')
    end

    it 'removes an account' do
      config.remove_account('main')
      expect(config.account_exists?('main')).to be false
      expect(config.account_exists?('trading')).to be true
    end
  end

  describe '#clear_accounts' do
    before do
      config.add_account('main', '12345678')
      config.default_account = 'main'
    end

    it 'clears all accounts and default account' do
      config.clear_accounts
      expect(config.account_names).to be_empty
      expect(config.default_account).to be_nil
    end
  end
end

RSpec.describe OptionsTrader do
  before do
    described_class.instance_variable_set(:@configuration, nil)
  end

  describe 'module-level account methods' do
    it 'provides convenience methods for account management' do
      OptionsTrader.add_account('main', '12345678')
      OptionsTrader.add_account('trading', '87654321')

      expect(OptionsTrader.account_number('main')).to eq('12345678')
      expect(OptionsTrader.account_names).to contain_exactly('main', 'trading')
      expect(OptionsTrader.account_exists?('main')).to be true
      expect(OptionsTrader.account_exists?('unknown')).to be false
    end

    it 'allows setting a default account' do
      OptionsTrader.default_account = 'main'
      expect(OptionsTrader.default_account).to eq('main')
    end
  end

  describe '.configure' do
    it 'allows configuration via block' do
      OptionsTrader.configure do |config|
        config.add_account('main', '12345678')
        config.default_account = 'main'
        config.log_level = :debug
      end

      expect(OptionsTrader.account_number('main')).to eq('12345678')
      expect(OptionsTrader.default_account).to eq('main')
      expect(OptionsTrader.configuration.log_level).to eq(:debug)
    end
  end
end
