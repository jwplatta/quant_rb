require 'rspec'
require_relative '../../../../services/schwab/data_objects/transaction'

RSpec.describe DataObjects::Transaction do
  let(:raw_data) do
    {}
    # JSON.parse(File.read('spec/fixtures/transaction.json'), symbolize_names: true)
  end
  describe '.build' do
    xit 'creates an transaction object from raw data' do
      transaction = DataObjects::Transaction.build(raw_data)
      expect(transaction).to be_an_instance_of Transaction
    end
  end
end
