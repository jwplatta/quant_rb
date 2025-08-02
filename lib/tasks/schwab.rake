# frozen_string_literal: true

require 'json'
require 'csv'
require 'date'
require 'gruff'
require 'fileutils'
require_relative '../options_trader'

class SchwabClient
  include OptionsTrader::Schwab
end

schwab_client = SchwabClient.new

namespace :schwab do
  desc 'Refresh Schwab token'
  task :refresh_token do
    script_path = File.join(Dir.pwd, 'bin', 'refresh_token.rb')
    sh "ruby #{script_path}"
    puts 'Token refreshed'
  end

  desc 'Find Options Strategy'
  task :find_strategy, %i[
    account_name
    underlying
    strategy_type
    short_delta
    max_spread
    min_credit
    min_open_interest
    dist_from_strike
    quantity
    settlement_type
    end_date
  ] => :environment do |t, args|
    account_name = args[:account_name]
    if account_name
      schwab_client.set_account(account_name)
      puts "Using account: #{account_name}"
    else
      puts "No account specified. Please provide an account name as a parameter."
      puts "Available accounts: #{schwab_client.available_accounts.join(', ')}"
      exit
    end

    underlying = if args.underlying
                   args.underlying
                 else
                   puts 'Please provide an underlying symbol'
                   exit
                 end

    strategy_type = if %W[iron_condor call_spread put_spread].include? args.strategy_type
                   args.strategy_type
                 else
                   puts 'Please provide a valid trade type (iron_condor, call_spread, put_spread)'
                   exit
                 end

    short_delta = args.fetch(:short_delta, 0.15).to_f
    max_spread = args.fetch(:max_spread, 20.0).to_f
    end_date = Date.parse(args.end_date) || Date.today + 30
    min_credit = args.fetch(:min_credit, 50.0).to_f
    min_open_interest = args.fetch(:min_open_interest, 0).to_i
    dist_from_strike = args.fetch(:dist_from_strike, 0.05).to_f
    quantity = args.fetch(:quantity, 1).to_i
    settlement_type = args.fetch(:settlement_type, 'P')

    puts "Finding #{strategy_type} for #{underlying} on #{end_date} with short delta #{short_delta}, " \
        "max spread #{max_spread}, " \
        "on date #{end_date}, min credit #{min_credit}, " \
        "min open interest #{min_open_interest}, " \
        "dist from strike #{dist_from_strike}, quantity #{quantity}" \
        " and settlement type #{settlement_type}"

    strategy = find_strategy(
      strategy_type,
      underlying,
      end_date,
      short_delta,
      max_spread,
      min_credit,
      min_open_interest,
      dist_from_strike,
      quantity,
      settlement_type
    )

    if strategy.type == 'putspread' || strategy.type == 'callspread'
      puts """
      ###########
      STRATEGY FOUND: #{strategy.type}
      ###########
      short leg symbol: #{strategy.short_leg.symbol}
      short leg strike: #{strategy.short_leg.strike}
      short leg open interest: #{strategy.short_leg.open_interest}

      long leg symbol: #{strategy.long_leg.symbol}
      long leg strike: #{strategy.long_leg.strike}
      long leg open interest: #{strategy.long_leg.open_interest}

      expiration date: #{strategy.expiration_date}
      credit/debit: #{strategy.credit}
      spread width: #{strategy.spread_width}
      delta: #{strategy.delta}
      """
    elsif strategy.type == 'ironcondor'
      puts """
      ###########
      STRATEGY FOUND: Iron Condor
      ###########
      expiration date: #{strategy.expiration_date}
      credit: #{strategy.credit}
      delta: #{strategy.delta}

      Call Spread:
      delta: #{strategy.call_spread.delta}
      spread width: #{strategy.call_spread.spread_width}
      short leg symbol: #{strategy.call_spread.short_leg.symbol}
      short leg strike: #{strategy.call_spread.short_leg.strike}
      long leg symbol: #{strategy.call_spread.long_leg.symbol}
      long leg strike: #{strategy.call_spread.long_leg.strike}

      Put Spread:
      delta: #{strategy.put_spread.delta}
      spread width: #{strategy.put_spread.spread_width}
      short leg symbol: #{strategy.put_spread.short_leg.symbol}
      short leg strike: #{strategy.put_spread.short_leg.strike}
      long leg symbol: #{strategy.put_spread.long_leg.symbol}
      long leg strike: #{strategy.put_spread.long_leg.strike}
      """
    else
      puts 'No strategy found'
    end

    schwab_client.build_and_preview_order(order_instruction: :open, **strategy.extract_kwargs(:open)).then do |preview_data|
      File.open('order_preview.json', 'w') { |f| f.write(preview_data.to_h.to_json) }
      puts "Order preview saved to order_preview.json"
    end
  rescue StandardError => e
    puts "Error finding strategy: #{e.message}"
  end

  desc 'Show Account'
  task :print_account, [:account_name] => :environment do |_t, args|
    account_name = args[:account_name]

    if account_name
      schwab_client.set_account(account_name)
      puts "Using account: #{account_name}"
    else
      puts "No account specified. Please provide an account name as a parameter."
      puts "Available accounts: #{schwab_client.available_accounts.join(', ')}"
      exit
    end

    account = schwab_client.account(fields: 'positions')
    account_summary = """
    Account Summary for #{account_name}:
    Cash Balance: #{account.current_balances.cash_balance}
    Liquidation Value: #{account.current_balances.liquidation_value}
    w/ Equity: #{account.current_balances.equity}
    Buying Power: #{account.current_balances.buying_power}
    """
    puts account_summary
    puts "\n-----------------------------------\n"
    puts "\nPOSITIONS:"

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
      elsif ['FIXED_INCOME', 'COLLECTIVE_INVESTMENT'].include?(position.instrument.asset_type)
        position_sum = """
        Symbol: #{position.instrument.symbol}
        Description: #{position.instrument.description}
        Average Price: #{position.average_price}
        Market Value: #{position.market_value}
        Long Quantity: #{position.long_quantity}
        Short Quantity: #{position.short_quantity}
        """
        puts position_sum
      else
        puts "Unknown asset type: #{position.instrument.asset_type}"
        puts position.instrument.inspect
      end
    end
  end

  desc 'List available accounts'
  task :list_accounts => :environment do
    accounts = schwab_client.available_accounts
    if accounts.empty?
      puts "No accounts configured. Please configure accounts using:"
      puts "OptionsTrader.configure do |config|"
      puts "  config.add_account('account_name', 'account_number')"
      puts "end"
    else
      puts "Available accounts:"
      accounts.each do |account_name|
        account_number = OptionsTrader.account_number(account_name)
        puts "  #{account_name}: #{account_number}"
      end
    end
  end

  task :puts_filled_orders do
    orders_resp = schwab_client.account_orders(
      from_date: Date.today - 5,
      status: 'FILLED'
    )
    File.open('data/orders/filled_orders.json', 'w') do |file|
      file << JSON.pretty_generate({
        orders: orders_resp.map(&:to_h)
      })
    end
  end

  desc 'Orders and Transactions'
  task :orders_and_transactions, [:account_name, :start_date, :end_date] => :environment do |_t, args|
    start_date = args[:start_date] ? Date.parse(args[:start_date]) : Date.today - 30
    end_date = args[:end_date] ? Date.parse(args[:end_date]).to_datetime.change({ hour: 23, min: 59, sec: 59 }) : Date.today.to_datetime.change({ hour: 23, min: 59, sec: 59 })
    account_name = args[:account_name]

    schwab_client.set_account(account_name)

    orders = schwab_client.account_orders(
      from_date: start_date,
      to_date: end_date,
      status: 'FILLED'
    )

    replaced_orders = schwab_client.account_orders(
      from_date: start_date,
      to_date: end_date,
      status: 'REPLACED'
    )

    orders += replaced_orders

    transactions = schwab_client.transactions(
      from_date: start_date,
      to_date: end_date,
      transaction_types: ['TRADE']
    )

    order_transactions = orders.map do |order|
      dtls = []
      transactions.select { |t| t.order_id == order.order_id }.each do |transaction|
        transaction.transfer_items.each do |item|
          if !item.fee_type.nil?
            dtls << [item.fee_type, "", item.cost, ""]
          elsif item.instrument.asset_type == 'OPTION'
            dtls << [item.instrument.symbol, item.instrument.description, item.cost, item.amount]
          else
            dtls << [item.instrument.symbol, item.instrument.description, item.cost, item.amount]
          end
        end
      end

      [order.order_id, dtls]
    end.to_h

    total = order_transactions.sum do |order_id, dtls|
      dtls.sum { |item| item[2] }
    end.round(2)

    order_totals = orders.map do |order|
      order_net_amt = transactions.select { |t| t.order_id == order.order_id }.sum do |transaction|
        transaction.net_amount
      end

      [order.order_id, order_net_amt]
    end.to_h

    net_amount_total = order_totals.sum do |order_id, net_amt|
      net_amt
    end.round(2)

    binding.pry
  end

  desc "Export Transactions by Order"
  task :export_transactions_by_order, [:account_names, :from_date, :to_date] => :environment do |_t, args|
    account_names = validate_account_names(schwab_client, args[:account_names])

    from_date = args[:from_date] ? Date.parse(args[:from_date]) : Date.today
    from_date = DateTime.new(from_date.year, from_date.month, from_date.day, 0, 0, 0)

    to_date = args[:to_date] ? Date.parse(args[:to_date]) : Date.today
    to_date = DateTime.new(to_date.year, to_date.month, to_date.day, 23, 59, 59)

    out_path = OptionsTrader::Exports::TransactionsByOrder.export(
      schwab_client: schwab_client,
      from_date: from_date,
      to_date: to_date,
      account_names: account_names
    )

    puts "Exported to: #{out_path}"
  end

  desc 'Monthly Report - supports single account or multiple accounts (comma-separated)'
  task :monthly_report, [:year, :accounts] => :environment do |_t, args|
    year = args[:year].to_i || Date.today.year
    accounts_arg = args[:accounts]
    account_names = validate_account_names(schwab_client, accounts_arg)

    chart = OptionsTrader::Charts::MonthlyProgress.new(schwab_client, account_names: account_names)
    filepath = chart.generate(year: year)

    if account_names.size == 1
      puts "Using account: #{account_names.first}"
    else
      puts "Using accounts: #{account_names.join(', ')}"
    end

    puts "Monthly report saved to #{filepath}"
  end

  desc 'Plot option open interest for a given underlying symbol, expiration date, and strike range'
  task :plot_open_interest, %i[
    underlying_symbol
    contract_type
    expiration_date
    min_strike
    max_strike
  ] => :environment do |_t, args|
    underlying_symbol = if args.underlying_symbol
               args.underlying_symbol
             else
               puts 'Please provide an underlying symbol'
               exit
             end

    contract_type = if %w[CALL PUT].include?(args.contract_type&.upcase)
                      args.contract_type.upcase
                    else
                      puts 'Please provide a valid contract type (CALL or PUT)'
                      exit
                    end

    begin
      expiration_date = Date.parse(args.expiration_date)
    rescue
      puts 'Please provide a valid expiration date (YYYY-MM-DD)'
      exit
    end

    min_strike = args.min_strike.to_f if args.min_strike
    max_strike = args.max_strike.to_f if args.max_strike

    puts "Fetching #{contract_type} options chain for #{symbol} with expiration date #{expiration_date}"

    opt_chain = schwab_client.option_chain(
      symbol,
      contract_type: contract_type,
      from_date: expiration_date,
      to_date: expiration_date
    )

    if opt_chain.nil?
      puts "No option chain found for #{symbol} on #{expiration_date}"
      exit
    end

    options = case contract_type
              when 'CALL'
                opt_chain.call_opts
              when 'PUT'
                opt_chain.put_opts
              end

    options = options.select { |opt| opt.expiration_date == expiration_date }

    if min_strike && max_strike
      options = options.select { |opt| opt.strike >= min_strike && opt.strike <= max_strike }
    elsif min_strike
      options = options.select { |opt| opt.strike >= min_strike }
    elsif max_strike
      options = options.select { |opt| opt.strike <= max_strike }
    end

    if options.empty?
      puts "No options found for #{symbol} on #{expiration_date} with the specified strike range"
      exit
    end

    options = options.sort_by(&:strike)

    chart = OptionsTrader::Charts::OpenInterest.new
    result = chart.generate(
      options,
      symbol: symbol,
      contract_type: contract_type,
      expiration_date: expiration_date
    )

    puts "Open interest plot created at #{result[:filepath]}"
  end
end

def validate_account_names(client, accounts_arg)
  unless accounts_arg
    puts "No accounts specified. Please provide account name(s) as a parameter."
    puts "Examples:"
    puts "  Single account:    rake schwab:monthly_report[2025,main]"
    puts "  Multiple accounts: rake schwab:monthly_report[2025,\"main,trading|ira\"]"
    puts "Available accounts: #{client.available_accounts.join(', ')}"
    exit
  end

  account_names = accounts_arg.split('|').map(&:strip)
  available_accounts = client.available_accounts
  invalid_accounts = account_names - available_accounts

  unless invalid_accounts.empty?
    puts "Invalid accounts: #{invalid_accounts.join(', ')}"
    puts "Available accounts: #{available_accounts.join(', ')}"
    exit
  end

  account_names
end

def find_strategy(
  strategy_type, underlying,
  end_date, short_delta,
  max_spread, min_credit,
  min_open_interest, dist_from_strike,
  quantity, settlement_type
)
  finder = case strategy_type
           when 'iron_condor'
             OptionsTrader::IronCondorFinder.new(
               underlying_symbol: underlying,
               expiration_date: end_date,
               quantity: quantity,
               settlement_type: settlement_type
             )
           when 'call_spread'
             OptionsTrader::CallSpreadFinder.new(
               underlying_symbol: underlying,
               expiration_date: end_date,
               quantity: quantity,
               settlement_type: settlement_type
             )
           when 'put_spread'
             OptionsTrader::PutSpreadFinder.new(
               underlying_symbol: underlying,
               expiration_date: end_date,
               quantity: quantity,
               settlement_type: settlement_type
             )
           else
             raise ArgumentError, "Invalid strategy type: #{strategy_type}"
           end

  finder.search(
    short_delta: short_delta,
    max_spread: max_spread,
    min_credit: min_credit,
    min_open_interest: min_open_interest,
    dist_from_strike: dist_from_strike
  )
end
