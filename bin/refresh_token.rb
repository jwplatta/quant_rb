# frozen_string_literal: true

require 'pry'
require 'dotenv'
require 'schwab_rb'

Dotenv.load

token_path = ENV['TOKEN_PATH']
puts "Token path: #{token_path}"

SchwabRb::Auth.init_client_easy(
  ENV['SCHWAB_API_KEY'],
  ENV['SCHWAB_APP_SECRET'],
  ENV['APP_CALLBACK_URL'],
  token_path
)
