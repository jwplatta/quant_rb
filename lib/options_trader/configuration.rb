module OptionsTrader
  class Configuration
    class << self
      def load
        new.tap do |config|
          config.load_accounts_from_env
        end
      end
    end

    attr_accessor :log_level, :log_file, :log_to_stdout,
                  :database_url, :db_host, :db_port, :db_name, :db_user, :db_password, :db_pool_size

    def accounts
      load_from_env_if_empty
      @accounts
    end

    def initialize
      @log_level = :info
      @log_file = nil
      @log_to_stdout = true
      @accounts = {}
      load_database_config_from_env
    end

    def add_account(name, account_number)
      @accounts[name.to_s] = account_number.to_s
    end

    def add_accounts(accounts_hash)
      accounts_hash.each do |name, number|
        add_account(name, number)
      end
    end

    def load_accounts_from_env
      ENV.select { |key, _| key.end_with?('_ACCOUNT') }.each do |key, value|
        account_name = key.gsub('_ACCOUNT', '').downcase
        add_account(account_name, value)
      end
    end

    def load_database_config_from_env
      @database_url = ENV['DATABASE_URL']
      @db_host = ENV['DATABASE_HOST']
      @db_port = ENV['DATABASE_PORT'] || 5432
      @db_name = ENV['DATABASE_NAME']
      @db_user = ENV['DATABASE_USER']
      @db_password = ENV['DATABASE_PASSWORD']
      @db_pool_size = (ENV['DB_POOL_SIZE'] || 15).to_i
    end

    def account_number(name)
      accounts[name.to_s]
    end

    def account_names
      accounts.keys
    end

    def account_exists?(name)
      accounts.key?(name.to_s)
    end

    def remove_account(name)
      @accounts.delete(name.to_s)
    end

    def clear_accounts
      @accounts.clear
    end

    def database_configured?
      !@database_url.nil? || (!@db_host.nil? && !@db_name.nil? && !@db_user.nil?)
    end

    private

    def load_from_env_if_empty
      load_accounts_from_env if @accounts.empty?
    end
  end

  # NOTE: OptionsTrader.configure
  class << self
    def configure
      yield configuration
    end

    def configuration
      @configuration ||= Configuration.new
    end

    def logger
      OptionsTrader::Logger.logger
    end

    def load_accounts_from_env
      configuration.load_accounts_from_env
    end

    def add_account(name, account_number)
      configuration.add_account(name, account_number)
    end

    def add_accounts(accounts_hash)
      configuration.add_accounts(accounts_hash)
    end

    def account_number(name)
      configuration.account_number(name)
    end

    def account_names
      configuration.account_names
    end

    def account_exists?(name)
      configuration.account_exists?(name)
    end

    def remove_account(name)
      configuration.remove_account(name)
    end

    def clear_accounts
      configuration.clear_accounts
    end

    def database_configured?
      configuration.database_configured?
    end

    def database_url
      configuration.database_url
    end

    def db_host
      configuration.db_host
    end

    def db_port
      configuration.db_port
    end

    def db_name
      configuration.db_name
    end

    def db_user
      configuration.db_user
    end

    def db_password
      configuration.db_password
    end

    def db_pool_size
      configuration.db_pool_size
    end
  end
end
