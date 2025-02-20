require 'pry'
require 'dotenv'
require 'schwab_rb'
require 'json'
require_relative '../data_objects/account'
require_relative '../data_objects/order'
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
  DataObjects::Account.build(acct_raw)
end

binding.pry

orders_resp = client.get_account_orders(
  account_hash,
  from_entered_datetime: Date.new(2025, 1, 1),
  to_entered_datetime: Date.new(2025, 1, 30),
  status: "FILLED"
)
filled_orders = JSON.parse(orders_resp.body, symbolize_names: true).then do |orders|
  orders.map { |o| DataObjects::Order.build(o) }
end

portfolio = Portfolio.build(filled_orders, account)
puts portfolio.to_h

portfolio.positions.each do |position|
  puts "#{position.symbols}: #{position.progress}"
end

binding.pry