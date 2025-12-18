# frozen_string_literal: true

require 'pry'
require 'dotenv'
require 'schwab_rb'

Dotenv.load

token_path = ENV['SCHWAB_TOKEN_PATH']
puts "Token path: #{token_path}"

client = SchwabRb::Auth.init_client_easy(
  ENV['SCHWAB_API_KEY'],
  ENV['SCHWAB_APP_SECRET'],
  ENV['SCHWAB_APP_CALLBACK_URL'],
  token_path
)

client.refresh_token if client.session.expired?
client.get_account_numbers