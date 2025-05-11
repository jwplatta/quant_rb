# frozen_string_literal: true

require 'pry'
require 'dotenv'
require 'json'
require 'csv'
require 'schwab_rb'
require 'date'
require_relative '../../mixins/schwab/data_objects/position'
require_relative '../../mixins/schwab/data_objects/account'
require_relative '../../mixins/schwab/data_objects/transaction'
require_relative '../../mixins/schwab/data_objects/order'
require_relative '../../mixins/schwab/data_objects/quote'
require_relative '../../services/search/iron_condor_finder'
require_relative '../../services/search/call_spread_finder'
require_relative '../../services/search/put_spread_finder'

Dotenv.load

Trade = Struct.new(
  :opening,
  :closing
)

class SchwabClient
  include Schwab
end

schwab_client = SchwabClient.new

namespace :schwab do
  desc 'Refresh Schwab token'
  task :refresh_token do
    script_path = File.join(Dir.pwd, 'bin', 'refresh_token.rb')

    sh "ruby #{script_path}"

    puts 'Token refreshed'
  end

  desc 'Get Quote'
  task :get_quote, [:symbol] => :environment do |_t, args|
    symbol = args[:symbol]
    quote = schwab_client.get_quote(symbol)
    puts quote
  end

  desc 'Find Options Trade'
  task :find_option_trade, %i[
    underlying trade_type short_delta max_spread days_to_expiration
    min_credit min_open_interest dist_from_strike quantity
  ] => :environment do |t, args|
    underlying = if args[:underlying]
                   args[:underlying]
                 else
                   puts 'Please provide an underlying symbol'
                   exit
                 end

    trade_type = if %W[iron_condor call_spread put_spread].include? args[:trade_type]
                   args[:trade_type]
                 else
                   puts 'Please provide a valid trade type (iron_condor, call_spread, put_spread)'
                   exit
                 end
    short_delta = args.fetch(:short_delta, 0.15).to_f
    max_spread = args.fetch(:max_spread, 20.0).to_f
    end_date = Date.today + args.fetch(:days_to_expiration, 30).to_i
    min_credit = args.fetch(:min_credit, 0.0).to_f
    min_open_interest = args.fetch(:min_open_interest, 0).to_i
    dist_from_strike = args.fetch(:dist_from_strike, 0.07).to_f
    quantity = args.fetch(:quantity, 1).to_i

    finder = trade_finder(
      trade_type,
      underlying,
      end_date,
      short_delta,
      max_spread,
      min_credit,
      min_open_interest,
      dist_from_strike,
      quantity
    )

    trade = finder.search
    if trade
      puts "Trade found: #{trade}"
    else
      puts 'No trade found'
    end
  end

  desc 'Show Account'
  task :puts_account do
    account = schwab_client.account(fields: 'positions')
    account_summary = """
    Account Summary:
    Cash Balance: #{account.current_balances.cash_balance}
    Liquidation Value: #{account.current_balances.liquidation_value}
    w/ Equity: #{account.current_balances.equity}
    Buying Power: #{account.current_balances.buying_power}
    """
    puts account_summary
    puts "\n-----------------------------------\n"
    puts "\nPositions:"

    account.positions.each do |position|
      if position.instrument.asset_type == 'EQUITY'
        position_sum = """
        Symbol: #{position.instrument.symbol}
        Average Price: #{position.average_price}
        Long Open Profit Loss: #{position.long_open_profit_loss}
        Market Value: #{position.market_value}
        Long Quantity: #{position.long_quantity}
        Settled Long Quantity: #{position.settled_long_quantity}
        Short Quantity: #{position.short_quantity}
        Settled Short Quantity: #{position.settled_short_quantity}
        --------------------------------------------------------------
        """
        puts position_sum
      elsif position.instrument.asset_type == 'OPTION'
        position_sum = """
        Symbol: #{position.instrument.symbol}
        Description: #{position.instrument.description}
        Average Price: #{position.average_price}
        Market Value: #{position.market_value}
        Long Open Profit Loss: #{position.long_open_profit_loss}
        Long Quantity: #{position.long_quantity}
        Settled Long Quantity: #{position.settled_long_quantity}
        Short Quantity: #{position.short_quantity}
        Settled Short Quantity: #{position.settled_short_quantity}
        --------------------------------------------------------------
        """
        puts position_sum
      else
        puts "Unknown asset type: #{position.instrument.asset_type}"
      end
    end
  end

  desc 'Write positions to CSV'
  task :positions_to_csv do
    account = schwab_client.account(account_hash, fields: 'positions')

    account.positions.each do |position|
      puts position.to_h
    end
  end

  task :puts_filled_orders do
    orders_resp = schwab_client.account_orders(
      from_entered_datetime: Date.today,
      status: 'FILLED'
    )
    binding.pry
  end

  desc 'Print trades'
  task :puts_trades do
    transactions = schwab_client.transactions(
      start_date: Date.new(2025, 1, 1),
      transaction_types: ['TRADE']
    )
    binding.pry
    # CSV.open('all_trades.csv', 'w', write_headers: true, headers: headers) do |csv|
    #   rows.each do |row|
    #     csv << row
    #   end
    # end
  end
end

def trade_finder(trade_type, underlying, end_date, short_delta, max_spread, min_credit, min_open_interest,
                 dist_from_strike, quantity)
  case trade_type
  when 'iron_condor'
    Services::Search::IronCondorFinder.new(
      symbol: underlying,
      end_date: end_date,
      short_delta: short_delta,
      max_spread: max_spread,
      min_credit: min_credit,
      min_open_interest: min_open_interest,
      dist_from_strike: dist_from_strike,
      quantity: quantity
    )
  when 'call_spread'
    Services::Search::CallSpreadFinder.new(
      symbol: underlying,
      end_date: end_date,
      short_delta: short_delta,
      max_spread: max_spread,
      min_credit: min_credit,
      min_open_interest: min_open_interest,
      dist_from_strike: dist_from_strike,
      quantity: quantity
    )
  when 'put_spread'
    Services::Search::PutSpreadFinder.new(
      symbol: underlying,
      end_date: end_date,
      short_delta: short_delta,
      max_spread: max_spread,
      min_credit: min_credit,
      min_open_interest: min_open_interest,
      dist_from_strike: dist_from_strike,
      quantity: quantity
    )
  else
    raise ArgumentError, "Invalid trade type: #{trade_type}"
  end
end
