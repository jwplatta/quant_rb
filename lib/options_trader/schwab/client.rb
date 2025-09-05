# frozen_string_literal: true

require 'schwab_rb'
require 'singleton'

module OptionsTrader
  module Schwab
    class Client
      include Singleton

      def initialize
        @client = SchwabRb::Auth.init_client_easy(
          ENV['SCHWAB_API_KEY'],
          ENV['SCHWAB_APP_SECRET'],
          ENV['APP_CALLBACK_URL'],
          ENV['TOKEN_PATH']
        )
      end

      def method_missing(method_name, *args, &block)
        if @client.respond_to?(method_name)
          @client.public_send(method_name, *args, &block)
        else
          super
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        @client.respond_to?(method_name) || super
      end
    end
  end
end
