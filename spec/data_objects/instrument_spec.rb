require 'rspec'
require_relative '../../data_objects/instrument'

RSpec.describe DataObjects::Instrument do
  let(:raw_data) do
    {}
    # JSON.parse(File.read('spec/fixtures/instrument.json'), symbolize_names: true)
  end
  describe '.build' do
    xit 'creates an instrument object from raw data' do
      instrument = DataObjects::Instrument.build(raw_data)
      expect(instrument).to be_an_instance_of Instrument
    end
  end
end
