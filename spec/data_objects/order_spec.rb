require 'rspec'
require_relative '../../data_objects/order'

RSpec.describe DataObjects::Order do
  let(:raw_data) do
    JSON.parse(File.read('spec/fixtures/orders.json'), symbolize_names: true)
  end
  describe '.build' do
    it 'creates an order object from raw data' do
      raw_data.each do |data|
        order = DataObjects::Order.build(data)
        expect(order).to be_an_instance_of DataObjects::Order
        order.order_leg_collection.each do |leg|
          expect(leg).to be_an_instance_of DataObjects::OrderLeg
        end

        order.order_activity_collection.each do |activity|
          expect(activity).to be_an_instance_of DataObjects::OrderActivity
          activity.execution_legs.each do |execution_leg|
            expect(execution_leg).to be_an_instance_of DataObjects::ExecutionLeg
          end
        end
      end
    end
  end
end
