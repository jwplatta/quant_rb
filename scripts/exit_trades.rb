# frozen_string_literal: true

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

accounts_resp = JSON.parse(client.get_account_numbers.body)
account_hash = accounts_resp.first['hashValue']

puts "Getting transactions for account: #{account_hash}"

transactions_resp = client.get_transactions(account_hash, start_date: Date.new(2025, 1, 1))
transactions = JSON.parse(transactions_resp.body, symbolize_names: true)

all_trades = transactions.select { |t| t['type'] == 'TRADE' }

binding.pry

first_trade = all_trades.first
# 1002613435352
# 1002613435352

order_resp = client.get_order(first_trade['orderId'], account_hash)
order = JSON.parse(order_resp.body, symbolize_names: true)

binding.pry
