#!/usr/bin/env ruby

require_relative '../../config/environment'
require_relative '../../lib/options_trader'
require 'date'
require 'pry'

spx_index = '$SPX'
vix_index = '$VIX'
vix9d_index = '$VIX9D'
vix3m_index = '$VIX3M'
vvix_index = '$VVIX'
skew_index = '$SKEW'

interval_min = 5

provider = OptionsTrader::DataProviders::Schwab::Markets.new
window = 60
end_time = Time.new(2025, 1, 29, 16, 0, 0, '-04:00') # market close (Eastern)
start_time = Time.new(2025, 1, 29, 9, 30, 0, '-04:00') # market open (Eastern)
start_datetime = start_time.to_datetime
end_datetime = end_time.to_datetime
start_datetime = (end_time - 60 * interval_min * window).to_datetime

puts "Fetching price history from #{start_datetime} to #{end_datetime}..."

# spx_price_hist = provider.get_price_history_every_five_min(
#   symbol: spx_index,
#   start_datetime: start_datetime,
#   end_datetime: end_datetime
# )

vix_price_hist = provider.get_price_history_every_five_min(
  symbol: vix_index,
  start_datetime: start_datetime,
  end_datetime: end_datetime
)

# vix9d_price_hist = provider.get_price_history_every_five_min(
#   symbol: vix9d_index,
#   start_datetime: start_datetime,
#   end_datetime: end_datetime
# )

# vix3m_price_hist = provider.get_price_history_every_five_min(
#   symbol: vix3m_index,
#   start_datetime: start_datetime,
#   end_datetime: end_datetime
# )

# vvix_price_hist = provider.get_price_history_every_five_min(
#   symbol: vvix_index,
#   start_datetime: start_datetime,
#   end_datetime: end_datetime
# )

skew_price_hist = provider.get_price_history_every_five_min(
  symbol: skew_index,
  start_datetime: start_datetime,
  end_datetime: end_datetime
)

quotes = provider.get_quotes([spx_index, vix_index, vix9d_index, vix3m_index, vvix_index, skew_index])

binding.pry