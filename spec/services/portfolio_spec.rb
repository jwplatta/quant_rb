require 'rspec'
require 'pry'
require_relative '../../services/portfolio'
require_relative '../../services/schwab/data_objects/order'
require_relative '../../services/schwab/data_objects/account'

RSpec.describe Portfolio do
  let(:orders) do
    JSON.parse(File.read('spec/fixtures/orders_with_close.json'), symbolize_names: true).then do |data|
      data.map { |order| DataObjects::Order.build(order) }
    end
  end
  let(:account) do
    JSON.parse(File.read('spec/fixtures/account.json'), symbolize_names: true).then do |data|
      DataObjects::Account.build(data)
    end
  end
  describe '.build' do
    it 'creates an portfolio object from raw data' do
      portfolio = Portfolio.build(orders, account)
      expect(portfolio.positions.count).to eq(4)
    end
  end
end
