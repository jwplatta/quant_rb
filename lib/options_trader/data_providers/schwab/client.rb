# frozen_string_literal: true

require 'schwab_rb'
require 'singleton'

module OptionsTrader
  module DataProviders
    module Schwab
      class Client
        include Singleton

        def initialize
          validate_environment
          @client = SchwabRb::Auth.init_client_easy(
            ENV['SCHWAB_API_KEY'],
            ENV['SCHWAB_APP_SECRET'],
            ENV['SCHWAB_APP_CALLBACK_URL'],
            ENV['SCHWAB_TOKEN_PATH']
          )
        end

        def method_missing(method_name, *args, **kwargs, &block)
          if @client.respond_to?(method_name)
            @client.public_send(method_name, *args, **kwargs, &block)
          else
            super
          end
        end

        def respond_to_missing?(method_name, include_private = false)
          @client.respond_to?(method_name) || super
        end

        private

        def validate_environment
          required_vars = %w[SCHWAB_API_KEY SCHWAB_APP_SECRET SCHWAB_APP_CALLBACK_URL SCHWAB_TOKEN_PATH]
          missing_vars = required_vars.select { |var| ENV[var].nil? || ENV[var].empty? }

          unless missing_vars.empty?
            raise Base::AuthenticationError, "Missing required environment variables: #{missing_vars.join(', ')}"
          end
        end
      end
    end
  end
end
