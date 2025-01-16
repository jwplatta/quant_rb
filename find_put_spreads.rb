require 'bundler/setup'
Bundler.require

require 'pry'
require 'dotenv'
require 'schwab_rb'
require 'json'
require 'csv'

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
  resp = client.get_option_chain(ticker, contract_type: 'PUT', to_date: Date.new(2025, 4, 1))
  File.open("./data/#{ticker.gsub("/", "")}_option_chain.json", 'w') do |f|
    f.write(resp.body)
  end
end

# NOTE
# less than the 15-delta
# 2 to 20 point spread (in strike price for stocks)
# verify that the strikes are at least 7% away from the current underlying price
# credit should be at least $100
# should receive at least 12% on buying power (or capital required)

trade_cnt = 0
trades = []

# tickers = ["TSLA"]

tickers.each do |ticker|
  option_chain = File.open("./data/#{ticker.gsub("/", "")}_option_chain.json", 'r') do |f|
    JSON.parse(f.read)
  end

  underlying_price = option_chain['underlyingPrice']
  volatility = option_chain['volatility']
  avail_puts = option_chain['putExpDateMap']
  puts "=============================="
  puts "Underlying Price: #{ticker} #{underlying_price}"
  avail_puts.each do |exp_date, strikes|
    strikes_with_low_deltas = strikes.select do |strike, data|
      data.first['delta'].abs <= 0.15 && data.first['openInterest'] > 0
    end

    puts "Looking at #{strikes_with_low_deltas.size} strikes for #{ticker} #{exp_date}."

    strikes_with_low_deltas.each do |short_strike, data|
      short_delta = data.first['delta']
      short_bid = data.first['bid']
      short_ask = data.first['ask']
      short_mark = data.first['mark']

      strike_diff = ((short_strike.to_f - underlying_price) / underlying_price).abs

      next unless short_mark * 100.0 >= 100.0 && strike_diff >= 0.07

      lower_bound = short_strike.to_f - 20.0
      upper_bound = short_strike.to_f
      lower_strikes = strikes_with_low_deltas.keys.map(&:to_f).select do |lower_strike|
        (lower_bound...upper_bound).cover? lower_strike
      end

      valid_spreads = lower_strikes.select do |long_strike|
        strike_data = strikes[long_strike.to_s].first

        long_open_interest = strike_data['openInterest']
        long_bid = strike_data['bid']

        long_ask = strike_data['ask']
        long_mid = (long_bid + long_ask) / 2.0

        (short_mark - long_mid) * 100.0 >= 100.0 && long_open_interest > 0
      end

      puts "Found #{valid_spreads.size} valid spreads for #{ticker} #{exp_date} #{short_strike}."

      if valid_spreads.any?
        trade_cnt += 1
        trades << [trade_cnt, ticker, exp_date, "SELL", short_strike, short_delta, short_bid, short_ask, short_mark]

        valid_spreads.each do |long_strike|
          strike_data = strikes[long_strike.to_s].first
          long_delta = strike_data['delta']
          long_bid = strike_data['bid']
          long_ask = strike_data['ask']
          long_mid = (long_bid + long_ask) / 2.0

          trades << [trade_cnt, ticker, exp_date, "BUY", long_strike, long_delta, long_bid, long_ask, long_mid]
        end
      end
    end
  end
end

puts "Found #{trade_cnt} trades."

headers = ["Trade", "Symbol", "Exp Date", "BUY/SELL", "Strike", "Delta", "Bid", "Ask", "Mid"]
CSV.open("put_spreads.csv", "w", write_headers: true, headers: headers) do |csv|
  trades.each do |trade|
    csv << trade
  end
end