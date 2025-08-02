require 'active_record'

module OptionsTrader
  module DB
    def self.connect!
      config = build_config
      ActiveRecord::Base.establish_connection(config)
    end

    def self.connected?
      ActiveRecord::Base.connected?
    rescue
      false
    end

    def self.disconnect!
      ActiveRecord::Base.connection_pool.disconnect!
    end

    private

    def self.build_config
      unless OptionsTrader.database_configured?
        raise "Database not configured. Set DATABASE_URL or individual DB environment variables."
      end

      if OptionsTrader.database_url
        { url: OptionsTrader.database_url }
      else
        {
          adapter: 'postgresql',
          host: OptionsTrader.db_host,
          port: OptionsTrader.db_port,
          database: OptionsTrader.db_name,
          username: OptionsTrader.db_user,
          password: OptionsTrader.db_password,
          pool: OptionsTrader.db_pool_size
        }
      end
    end
  end
end