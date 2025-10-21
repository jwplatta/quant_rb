module OptionsTrader
  class Configuration
    class << self
      def load
        new.tap do |config|
          config.load_accounts_from_env
        end
      end
    end

    attr_accessor :log_level, :log_file, :log_to_stdout
    attr_accessor :greek_forge_host, :greek_forge_port, :greek_forge_scheme

    def accounts
      load_from_env_if_empty
      @accounts
    end

    def initialize
      @log_level = :info
      @log_file = nil
      @log_to_stdout = true
      @accounts = {}

      # Greek Forge configuration
      @greek_forge_host = ENV['GREEK_FORGE_HOST'] || 'localhost'
      @greek_forge_port = (ENV['GREEK_FORGE_PORT'] || '8000').to_i
      @greek_forge_scheme = ENV['GREEK_FORGE_SCHEME'] || 'http'
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
  end
end
