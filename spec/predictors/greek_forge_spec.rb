require 'spec_helper'

RSpec.describe OptionsTrader::Predictors::GreekForge do
  let(:client) { described_class.new }

  before do
    OptionsTrader.configuration.greek_forge_host = 'localhost'
    OptionsTrader.configuration.greek_forge_port = 8000
    OptionsTrader.configuration.greek_forge_scheme = 'http'
  end

  describe '#initialize' do
    it 'uses configuration defaults' do
      expect(client.host).to eq('localhost')
      expect(client.port).to eq(8000)
      expect(client.scheme).to eq('http')
    end

    it 'allows overriding configuration' do
      custom_client = described_class.new(host: 'custom-host', port: 9000, scheme: 'https')
      expect(custom_client.host).to eq('custom-host')
      expect(custom_client.port).to eq(9000)
      expect(custom_client.scheme).to eq('https')
    end
  end

  describe '#predict_deltas' do
    let(:payload) do
      {
        contract_type: 'CALL',
        features: [
          { dte: 5, moneyness: 0.99, mark: 10.5, strike: 6000.0, underlying_price: 6300.0, vix9d: 15.0, vvix: 90.0, skew: 140.0 }
        ],
        version: 'latest'
      }
    end

    it 'raises ConnectionError when connection refused' do
      allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED)

      expect { client.predict_deltas(payload) }.to raise_error(
        OptionsTrader::Predictors::GreekForge::ConnectionError,
        /connection failed/
      )
    end

    it 'raises TimeoutError on timeout' do
      allow(Net::HTTP).to receive(:start).and_raise(Net::ReadTimeout)

      expect { client.predict_deltas(payload) }.to raise_error(
        OptionsTrader::Predictors::GreekForge::TimeoutError,
        /timeout/
      )
    end
  end
end
