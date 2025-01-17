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

tickers = File.open('sp_500_tickers.txt', 'r') do |f|
  f.read.split("\n")
end

tickers.each do |ticker|
  puts "=============================="
  puts "Getting option chain for #{ticker}"

  resp = client.get_option_chain(ticker, contract_type: 'PUT', to_date: Date.new(2025, 4, 1))
  path = "./data/#{ticker.gsub("/", "")}_option_chain.json"

  File.open(path, 'w') { |f| f.write(resp.body) }

  puts "Option chain saved to #{path}"
  puts "=============================="
end
