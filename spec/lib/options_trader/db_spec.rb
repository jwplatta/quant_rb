require 'spec_helper'

RSpec.describe OptionsTrader::DB do
  describe '.connected?' do
    context 'when database is connected' do
      it 'returns true' do
        allow(ActiveRecord::Base).to receive(:connected?).and_return(true)
        expect(OptionsTrader::DB.connected?).to be true
      end
    end

    context 'when database connection fails' do
      it 'returns false and logs warning' do
        allow(ActiveRecord::Base).to receive(:connected?).and_raise(ActiveRecord::ConnectionNotEstablished, 'Connection failed')
        expect(OptionsTrader.logger).to receive(:warn).with(/Database connection check failed/)
        expect(OptionsTrader::DB.connected?).to be false
      end
    end
  end

  describe '.build_config' do
    context 'when DATABASE_URL is set' do
      it 'returns URL-based configuration' do
        allow(OptionsTrader).to receive(:database_configured?).and_return(true)
        allow(OptionsTrader).to receive(:database_url).and_return('postgresql://user:pass@host:5432/db')
        
        config = OptionsTrader::DB.send(:build_config)
        expect(config).to eq({ url: 'postgresql://user:pass@host:5432/db' })
      end
    end

    context 'when individual DB params are set' do
      it 'returns parameter-based configuration' do
        allow(OptionsTrader).to receive(:database_configured?).and_return(true)
        allow(OptionsTrader).to receive(:database_url).and_return(nil)
        allow(OptionsTrader).to receive(:db_host).and_return('localhost')
        allow(OptionsTrader).to receive(:db_port).and_return(5432)
        allow(OptionsTrader).to receive(:db_name).and_return('test_db')
        allow(OptionsTrader).to receive(:db_user).and_return('postgres')
        allow(OptionsTrader).to receive(:db_password).and_return('password')
        allow(OptionsTrader).to receive(:db_pool_size).and_return(15)
        
        config = OptionsTrader::DB.send(:build_config)
        expect(config).to include(
          adapter: 'postgresql',
          host: 'localhost',
          port: 5432,
          database: 'test_db',
          username: 'postgres',
          password: 'password',
          pool: 15
        )
      end
    end

    context 'when database is not configured' do
      it 'raises an error' do
        allow(OptionsTrader).to receive(:database_configured?).and_return(false)
        
        expect {
          OptionsTrader::DB.send(:build_config)
        }.to raise_error(/Database not configured/)
      end
    end
  end
end