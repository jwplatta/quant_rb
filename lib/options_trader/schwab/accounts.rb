module OptionsTrader
  module Schwab
    class Accounts
      class << self
        def account_number(account_name)
          accounts[account_name.to_s] || raise("Account '#{account_name}' not found")
        end

        def account_hash(account_name, client)
          @account_hashes ||= {}
          @account_hashes[account_name.to_s] ||= fetch_account_hash(account_name, client)
        end

        def accounts
          @accounts ||= load_accounts
        end

        def account_names
          accounts.keys
        end

        private

        def load_accounts
          config_accounts = OptionsTrader.configuration.accounts
          return config_accounts unless config_accounts.empty?

          raise "No accounts configured. Please register accounts using OptionsTrader.add_account(name, number) or OptionsTrader.configure { |config| config.add_account(name, number) }"
        end

        def fetch_account_hash(account_name, client)
          account_number = account_number(account_name)

          client.get_account_numbers.then do |resp|
            account_data = JSON.parse(resp.body)
            account_info = account_data.find { |acc| acc['accountNumber'] == account_number }

            raise("Account number '#{account_number}' not found in Schwab response") unless account_info

            account_info['hashValue']
          end
        end
      end

      def initialize(account_name)
        @account_name = account_name
      end

      def account_number
        self.class.account_number(@account_name)
      end

      def account_hash(client)
        self.class.account_hash(@account_name, client)
      end
    end
  end
end
