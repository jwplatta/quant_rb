require 'pry'
require 'dotenv'
require 'json'
require 'csv'
require_relative 'models/option_chain'

# NOTE
# less than the 15-delta
# 2 to 20 point spread (in strike price for stocks)
# verify that the strikes are at least 7% away from the current underlying price
# credit should be at least $100
# should receive at least 12% on buying power (or capital required)
tickers = File.open('sp_500_tickers.txt', 'r') do |f|
  f.read.split("\n")
end

trade_cnt = 0
trades = []

def load_option_chain(ticker)
  path = "./data/#{ticker.gsub("/", "")}_option_chain.json"
  File.open(path, 'r') { |f| JSON.parse(f.read, symbolize_names: true) }.then do |data|
    OptionChain.from_raw(data)
  end
rescue StandardError => e
  puts "Error loading option chain for #{ticker}: #{e.message}"
  binding.pry
end

trades = []
trade_cnt = 0

tickers.each do |ticker|
  option_chain = load_option_chain(ticker)
  avail_puts = option_chain.put_opts

  puts "=============================="
  puts "Underlying Price: #{ticker} #{option_chain.underlying_price}"

  short_filters = [
    OptionFilter.new(attribute: :delta, comparison: "<=", value: 0.15),
    OptionFilter.new(attribute: :open_interest, comparison: ">", value: 0),
    OptionFilter.new(
      attribute: :strike,
      comparison: ->(strike) { ((option_chain.underlying_price - strike) / option_chain.underlying_price).abs >= 0.07 }
    ),
    OptionFilter.new(attribute: :mark, comparison: ->(mark) { mark * 100.0 >= 100.0 })
  ]

  potential_short_puts = option_chain.filter(put_call: :put, filters: short_filters)
  potential_short_puts.each do |short_put|
    long_filters = [
      OptionFilter.new(
        attribute: :strike,
        comparison: ->(strike) { ((short_put.strike - 20.0)...short_put.strike).cover? strike }
      ),
      OptionFilter.new(attribute: :open_interest, comparison: ">", value: 0),
      OptionFilter.new(attribute: :expiration_date, comparison: "==", value: short_put.expiration_date),
      OptionFilter.new(attribute: :mark, comparison: ->(mark) { (short_put.mark - mark) * 100.0 >= 100.0 })
    ]

    potential_long_puts = option_chain.filter(put_call: :put, filters: long_filters)

    if potential_long_puts.any?
      best_long_put = potential_long_puts.min_by(&:mark)
      trade_cnt += 1

      trades << [
        trade_cnt,
        ticker,
        option_chain.underlying_price.round(3),
        short_put.expiration_date.strftime('%Y-%m-%d'),
        short_put.days_to_expiration,
        "SELL",
        short_put.strike,
        short_put.delta,
        short_put.bid,
        short_put.ask,
        short_put.mark
      ]

      trades << [
        trade_cnt,
        "",
        "",
        "",
        "",
        "BUY",
        best_long_put.strike,
        best_long_put.delta,
        best_long_put.bid,
        best_long_put.ask,
        best_long_put.mark
      ]
    end
  end
end

puts "Found #{trade_cnt} trades."

headers = ["Trade", "Symbol", "Underlying Price", "Exp Date", "Days Left", "BUY/SELL", "Strike", "Delta", "Bid", "Ask", "Mid"]
CSV.open("put_spreads.csv", "w", write_headers: true, headers: headers) do |csv|
  trades.each do |trade|
    csv << trade
  end
end
