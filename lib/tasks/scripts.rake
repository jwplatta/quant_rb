require "pry"
require "dotenv"
require "json"
require "csv"
require "schwab_rb"
require "date"
require_relative "../../data_objects/position"
require_relative "../../data_objects/account"

Dotenv.load

token_path = ENV["TOKEN_PATH"]
client = SchwabRb::Auth.init_client_easy(
  ENV["SCHWAB_API_KEY"],
  ENV["SCHWAB_APP_SECRET"],
  ENV["APP_CALLBACK_URL"],
  token_path
)

namespace :scripts do
  desc "Check portfolio"
  task :check_portfolio do
    system("bundle exec ruby scripts/check_portfolio.rb")
    puts "✅ Portfolio checked!"
  end

  task :positions do
    accounts_resp = JSON.parse(client.get_account_numbers.body)
    account_hash = accounts_resp.first['hashValue']
    account_resp = client.get_account(account_hash, fields: 'positions')
    account = JSON.parse(account_resp.body, symbolize_names: true).then do |acct_raw|
      Account.build(acct_raw)
    end

    account.positions.each do |position|
      puts position.to_h
    end
  end
end
