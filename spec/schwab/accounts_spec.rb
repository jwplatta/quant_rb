# frozen_string_literal: true

RSpec.describe OptionsTrader::Schwab::Accounts do
  let(:mock_client) { double('SchwabRb::Client') }

  before do
    described_class.instance_variable_set(:@accounts, nil)
    described_class.instance_variable_set(:@account_hashes, nil)
    OptionsTrader.instance_variable_set(:@configuration, nil)
  end

  describe '.load_accounts' do
    it 'raises an error when no accounts are configured' do
      # Configuration should be empty (cleared in before block)
      expect {
        described_class.send(:load_accounts)
      }.to raise_error("No accounts configured. Please register accounts using OptionsTrader.add_account(name, number) or OptionsTrader.configure { |config| config.add_account(name, number) }")
    end

    it 'returns configuration accounts when they are set' do
      # Set up configuration accounts
      OptionsTrader.configuration.add_account('main', '99999999')
      OptionsTrader.configuration.add_account('trading', '88888888')

      accounts = described_class.send(:load_accounts)

      expect(accounts).to eq({
        'main' => '99999999',
        'trading' => '88888888'
      })
    end
  end

  describe '.account_names' do
    before do
      OptionsTrader.configuration.add_account('main', '12345678')
      OptionsTrader.configuration.add_account('trading', '87654321')
    end

    it 'returns available account names' do
      names = described_class.account_names
      expect(names).to contain_exactly('main', 'trading')
    end
  end

  describe '.account_number' do
    before do
      OptionsTrader.configuration.add_account('main', '12345678')
      OptionsTrader.configuration.add_account('trading', '87654321')
    end

    it 'returns the account number for a valid account name' do
      number = described_class.account_number('main')
      expect(number).to eq('12345678')
    end

    it 'accepts string or symbol account names' do
      expect(described_class.account_number('main')).to eq('12345678')
      expect(described_class.account_number(:main)).to eq('12345678')
    end

    it 'raises an error for unknown account names' do
      expect {
        described_class.account_number('unknown')
      }.to raise_error("Account 'unknown' not found")
    end
  end

  describe '.account_hash' do
    let(:account_numbers_response) do
      instance_double('Response', body: [
        { 'accountNumber' => '12345678', 'hashValue' => 'ABC123' },
        { 'accountNumber' => '87654321', 'hashValue' => 'XYZ789' }
      ].to_json)
    end

    before do
      OptionsTrader.configuration.add_account('main', '12345678')
      OptionsTrader.configuration.add_account('trading', '87654321')

      allow(mock_client).to receive(:get_account_numbers).and_return(account_numbers_response)
    end

    it 'fetches and returns the account hash for a given account' do
      hash_value = described_class.account_hash('main', mock_client)
      expect(hash_value).to eq('ABC123')
    end

    it 'caches account hashes to avoid repeated API calls' do
      # First call should hit the API
      expect(mock_client).to receive(:get_account_numbers).once.and_return(account_numbers_response)

      # Multiple calls should use cache
      hash1 = described_class.account_hash('main', mock_client)
      hash2 = described_class.account_hash('main', mock_client)

      expect(hash1).to eq('ABC123')
      expect(hash2).to eq('ABC123')
    end

    it 'raises an error when account number is not found in Schwab response' do
      # Mock response that doesn't include our account
      response = instance_double('Response', body: [
        { 'accountNumber' => '99999999', 'hashValue' => 'OTHER123' }
      ].to_json)

      allow(mock_client).to receive(:get_account_numbers).and_return(response)

      expect {
        described_class.account_hash('main', mock_client)
      }.to raise_error("Account number '12345678' not found in Schwab response")
    end
  end

  describe 'instance methods' do
    let(:account) { described_class.new('main') }

    before do
      OptionsTrader.configuration.add_account('main', '12345678')
    end

    describe '#account_number' do
      it 'returns the account number for the instance account name' do
        expect(account.account_number).to eq('12345678')
      end
    end

    describe '#account_hash' do
      let(:account_numbers_response) do
        instance_double('Response', body: [
          { 'accountNumber' => '12345678', 'hashValue' => 'ABC123' }
        ].to_json)
      end

      it 'returns the account hash for the instance account name' do
        allow(mock_client).to receive(:get_account_numbers).and_return(account_numbers_response)

        expect(account.account_hash(mock_client)).to eq('ABC123')
      end
    end
  end
end
