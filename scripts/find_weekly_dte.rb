# frozen_string_literal: true

require 'pry'
require 'dotenv'
require 'json'
require 'csv'
require 'schwab_rb'
require 'date'
require_relative 'mixins/schwab/data_objects/option_chain'
require_relative 'mixins/schwab/data_objects/position'
require_relative 'mixins/schwab/data_objects/instrument'
require_relative 'services/trades/call_spread'
require_relative 'services/trades/put_spread'
require_relative 'services/trades/iron_condor'

# NOTE:
# 1. check for economic news within the timeframe of the trade
# 2. use the SPX
# 3. Place trade from 7DTE to 14DTE
# 4. Not higher than a 10 delta on each side
#
# 5. 10 point spread
# - check the VIX
# - sell an iron condor
# - the short legs have to be 2 times the expected move away from the current strike price
# - collect at least $100

# try to exit the trade with 70% to 80% profit
# stop loss of $300 or 4x the credit received or whatever is less
# win expectancy is 85 to 90%

# STEPS:
# - need to find an iron condor that makes at least $100 in premium after fees
# - approximate fees are 4.88 for each iron condor
# - test creating an order through the api
# - test replacing an order
# - test canceling an order

# Expected Return=(Total Credit×POP)−(Total Risk×(1−POP))

Dotenv.load

token_path = ENV['SCHWAB_TOKEN_PATH']
client = SchwabRb::Auth.init_client_easy(
  ENV['SCHWAB_API_KEY'],
  ENV['SCHWAB_APP_SECRET'],
  ENV['SCHWAB_APP_CALLBACK_URL'],
  token_path
)

def get_spx_option_chain(client)
  today = Date.today
  client.get_option_chain(
    '$SPX',
    strike_range: 'OTM',
    from_date: today + 5,
    to_date: today + 5
  )
end

def option_chain_to_file(option_chain)
  path = './data/SPX_option_chain.json'
  File.open(path, 'w') { |f| f.write(option_chain) }
end

def load_option_chain
  path = './data/SPX_option_chain.json'
  File.open(path, 'r') { |f| JSON.parse(f.read, symbolize_names: true) }.then do |data|
    OptionChain.build(data)
  end
rescue StandardError => e
  puts "Error loading option chain: #{e.message}"
  binding.pry
end

get_spx_option_chain(client).then do |resp|
  raise "Error getting option chain: #{resp.body}" unless resp.status == 200

  option_chain_to_file(resp.body)
end

option_chain = load_option_chain
option_filters = [
  OptionFilter.new(attribute: :delta, comparison: '<=', value: 0.09)
]
put_opts = option_chain.filter(put_call: :put, filters: option_filters)
call_opts = option_chain.filter(put_call: :call, filters: option_filters)

best_trade = nil
best_credit = 0

# best_expected_return = -Float::INFINITY
# all_valid_combos_expected_return = []
# all_valid_combos = []
valid_trades = []

put_opts.combination(2).each do |long_put, short_put|
  next if short_put.strike < long_put.strike || (short_put.strike - 10) > long_put.strike

  put_spread = PutSpread.new(
    short_leg: Position.new(
      strike: short_put.strike,
      mark: short_put.mark,
      delta: short_put.delta,
      instrument: Instrument.new(
        symbol: short_put.symbol,
        underlying_symbol: short_put.underlying_symbol,
        description: short_put.description
      )
    ),
    long_leg: Position.new(
      strike: long_put.strike,
      mark: long_put.mark,
      delta: long_put.delta,
      instrument: Instrument.new(
        symbol: long_put.symbol,
        underlying_symbol: long_put.underlying_symbol,
        description: long_put.description
      )
    )
  )

  call_opts.combination(2).each do |short_call, long_call|
    next if short_call.strike > long_call.strike || (short_call.strike + 10) < long_call.strike

    call_spread = CallSpread.new(
      short_leg: Position.new(
        strike: short_call.strike,
        mark: short_call.mark,
        delta: short_call.delta,
        instrument: Instrument.new(
          symbol: short_call.symbol,
          underlying_symbol: short_call.underlying_symbol,
          description: short_call.description
        )
      ),
      long_leg: Position.new(
        strike: long_call.strike,
        mark: long_call.mark,
        delta: long_call.delta,
        instrument: Instrument.new(
          symbol: long_call.symbol,
          underlying_symbol: long_call.underlying_symbol,
          description: long_call.description
        )
      )
    )
    iron_condor = IronCondor.new(
      call_spread: call_spread,
      put_spread: put_spread
    )

    next unless iron_condor.credit_debit(include_fees: true) > 1.0
    next unless iron_condor.prob_of_profit >= 0.85

    # put_spread_width = (long_put.strike - short_put.strike).abs
    # call_spread_width = (long_call.strike - short_call.strike).abs
    # max_loss =([put_spread_width, call_spread_width].max - credit)
    # expected_return = calculate_expected_return(credit, max_loss, pop)
    valid_trades << [
      iron_condor.credit_debit,
      iron_condor.prob_of_profit,
      iron_condor.put_spread.spread_width,
      iron_condor.call_spread.spread_width,
      iron_condor.max_loss,
      iron_condor.expected_return,
      iron_condor.put_spread.delta.abs,
      iron_condor.call_spread.delta.abs
    ]

    if iron_condor.credit_debit > best_credit
      best_credit = iron_condor.credit_debit
      best_trade = iron_condor
    end
  end
end

headers = %w[
  credit pop put_spread_width call_spread_width max_loss
  expected_return short_put_delta short_call_delta
]

valid_trades.sort_by! { |trade| -trade.first }
CSV.open('valid_trades.csv', 'w', write_headers: true, headers: headers) do |csv|
  valid_trades.each do |trade|
    csv << trade
  end
end

# NOTE: returns a SchwabRb::Orders::Builder object
if best_trade.nil?
  puts 'No valid trades found'
  exit
else
  puts "
  credit_debit: #{best_trade.credit_debit}

  Strikes:
  put_short_leg_strike: #{best_trade.put_spread.short_leg.strike}
  put_long_leg_strike: #{best_trade.put_spread.long_leg.strike}
  call_short_leg_strike: #{best_trade.call_spread.short_leg.strike}
  call_long_leg_strike: #{best_trade.call_spread.long_leg.strike}

  Marks:
  put_short_leg_mark: #{best_trade.put_spread.short_leg.mark}
  put_long_leg_mark: #{best_trade.put_spread.long_leg.mark}
  call_short_leg_mark: #{best_trade.call_spread.short_leg.mark}
  call_long_leg_mark: #{best_trade.call_spread.long_leg.mark}

  Deltas:
  put_short_leg_delta: #{best_trade.put_spread.short_leg.delta}
  put_long_leg_delta: #{best_trade.put_spread.long_leg.delta}
  call_short_leg_delta: #{best_trade.call_spread.short_leg.delta}
  call_long_leg_delta: #{best_trade.call_spread.long_leg.delta}
  "
end

order = OrderFactory.build(
  best_trade,
  quantity: 1,
  account_number: ENV['SCHWAB_ACCOUNT_NUMBER']
)

accounts_resp = JSON.parse(client.get_account_numbers.body)
account_hash = accounts_resp.first['hashValue']

order_preview_resp = client.preview_order(account_hash, order)
File.open('preview_order_resp.json', 'w') do |f|
  f.write(order_preview_resp.body)
end

# if order_preview_resp.status == 200
#   puts "Order preview successful. Sending order"
#   order_resp = client.place_order(account_hash, order)
#   timestamp = Time.now.strftime("%Y%m%d%H%M%S")
#   File.open("order_#{timestamp}.json", "w") do |f|
#     f.write(order_resp.body)
#   end
# else
#   puts "Order preview failed"
# end

# headers = ["Exp Date", "Strike", "Type", "Delta", "Mark"]
# CSV.open("option_chain_table.csv", "w", write_headers: true, headers: headers) do |csv|
#   (call_opts + put_opts).each do |opt|
#     csv << opt
#   end
# end
