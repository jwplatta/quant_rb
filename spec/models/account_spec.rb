require 'rspec'
require 'pry'
require_relative '../../models/account'

RSpec.describe Account do
  let(:raw_data) do
    JSON.parse(File.read('spec/fixtures/account.json'), symbolize_names: true)
  end
  describe '.from_raw' do
    it 'creates an option chain object from raw data' do
      account = Account.build(raw_data)
      expect(account).to be_an_instance_of Account
      expect(account.type).to eq 'MARGIN'
      expect(account.account_number).to eq '11111111'
      expect(account.round_trips).to eq 0
      expect(account.is_closing_only_restricted).to be false
      expect(account.pfcb_flag).to be false
      expect(account.positions).to be_an_instance_of Array
      expect(account.positions.first).to be_an_instance_of Position
      expect(account.positions.first.instrument).to be_an_instance_of Instrument
      expect(account.initial_balances).to be_an_instance_of InitialBalances
      expect(account.current_balances).to be_an_instance_of CurrentBalances
      expect(account.projected_balances).to be_an_instance_of ProjectedBalances
    end
  end
end
