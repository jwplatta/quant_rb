require 'pry'
require 'dotenv'
require 'schwab_rb'
require 'json'
require_relative '../models/account'
require_relative '../models/order'
require_relative '../services/portfolio'

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

account_resp = client.get_account(account_hash, fields: 'positions')
account = JSON.parse(account_resp.body, symbolize_names: true).then do |acct_raw|
  Account.build(acct_raw)
end

orders_resp = client.get_account_orders(
  account_hash,
  from_entered_datetime: Date.new(2025, 1, 1),
  to_entered_datetime: Date.new(2025, 1, 30),
  status: "FILLED"
)
filled_orders = JSON.parse(orders_resp.body, symbolize_names: true).then do |orders|
  orders.map { |o| Order.build(o) }
end

portfolio = Portfolio.build(filled_orders, account)
