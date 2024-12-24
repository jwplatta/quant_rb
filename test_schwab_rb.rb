require 'pry'
require 'dotenv'
require 'schwab_rb'
require 'json'

Dotenv.load

token_path = ENV['TOKEN_PATH']

client = SchwabRb::Auth.init_client_easy(
  ENV['SCHWAB_API_KEY'],
  ENV['SCHWAB_APP_SECRET'],
  ENV['APP_CALLBACK_URL'],
  token_path
)

resp = client.get_accounts
accounts = JSON.parse(resp.body)
puts accounts

binding.pry