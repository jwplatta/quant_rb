# frozen_string_literal: true

require 'json'
require 'csv'
require 'date'
require 'gruff'
require 'fileutils'
require_relative '../platypi'

Trade = Struct.new(
  :opening,
  :closing
)

class SchwabClient
  include Platypi::Schwab
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
    quote = schwab_client.quote(symbol)

    puts "\n########\nSymbol: #{quote.symbol}\n########\n"
    puts "Description: #{quote.description}"
    puts "Mark: #{quote.mark}"
    puts "Delta: #{quote.delta}"
  end

  desc 'Find Options Trade'
  task :find_options_trade, %i[
    underlying trade_type
    short_delta max_spread
    end_date min_credit
    min_open_interest dist_from_strike
    quantity settlement_type
  ] => :environment do |t, args|
    underlying = if args.underlying
                   args.underlying
                 else
                   puts 'Please provide an underlying symbol'
                   exit
                 end

    trade_type = if %W[iron_condor call_spread put_spread].include? args.trade_type
                   args.trade_type
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

    puts "Finding #{trade_type} for #{underlying} on #{end_date} with short delta #{short_delta}, " \
        "max spread #{max_spread}, " \
        "on date #{end_date}, min credit #{min_credit}, " \
        "min open interest #{min_open_interest}, " \
        "dist from strike #{dist_from_strike}, quantity #{quantity}" \
        " and settlement type #{settlement_type}"

    contract_type = if trade_type == 'iron_condor'
      'ALL'
    elsif trade_type == 'call_spread'
      'CALL'
    elsif trade_type == 'put_spread'
      'PUT'
    else
      puts 'Invalid trade type'
      exit
    end

    opt_chain = schwab_client.option_chain(
      underlying,
      contract_type: contract_type,
      from_date: end_date,
      to_date: end_date
    )

    if opt_chain.nil?
      puts "No option chain found for #{underlying}"
      exit
    end

    finder = trade_finder(
      trade_type,
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

    trade = finder.search(opt_chain)

    if trade.type == 'putspread' || trade.type == 'callspread'
      puts """
      ###########
      TRADE FOUND: #{trade.type}
      ###########
      short leg symbol: #{trade.short_leg.symbol}
      short leg strike: #{trade.short_leg.strike}
      long leg symbol: #{trade.long_leg.symbol}
      long leg strike: #{trade.long_leg.strike}
      expiration date: #{trade.expiration_date}
      credit/debit: #{trade.credit}
      spread width: #{trade.spread_width}
      delta: #{trade.delta}
      open interest: #{trade.short_leg.open_interest}
      """
    elsif trade.type == :ironcondor
    else
      puts 'No trade found'
    end
  end

  desc 'Show Account'
  task :print_account do
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
    puts "\nPOSITIONs:"

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
      from_date: Date.today - 5,
      status: 'FILLED'
    )
    File.open('data/orders/filled_orders.json', 'w') do |file|
      file << JSON.pretty_generate({
        orders: orders_resp.map(&:to_h)
      })
    end
  end

  desc 'Print transactions'
  task :puts_transactions do
    transactions = schwab_client.transactions(
      from_date: Date.today - 30,
      to_date: Date.today,
      transaction_types: ['TRADE']
    )
    File.open('data/orders/transactions.json', 'w') do |file|
      file << JSON.pretty_generate({
        transactions: transactions.map(&:to_h)
      })
    end
    # CSV.open('all_trades.csv', 'w', write_headers: true, headers: headers) do |csv|
    #   rows.each do |row|
    #     csv << row
    #   end
    # end
  end

  desc 'Monthly Report'
  task :monthly_report, [:year] => :environment do |_t, args|
    year = args[:year] || Date.today.year
    totals = monthly_totals(schwab_client, year)
    dates = totals.map { |entry| entry.first.strftime("%b %d, %Y") }
    amounts = totals.map { |entry| entry[1] }

    g = Gruff::Bar.new(800)
    g.title = "Monthy Progress for #{year}"
    g.title_font_size = 20

    g.theme = {
      colors: %w[#006400 #DC143C #CCCCCC],
      marker_color: '#666666',
      font_color: '#333333',
      background_colors: %w[#ffffff #ffffff]
    }

    g.data(:amounts, amounts)

    g.hide_line_markers = false

    g.y_axis_label = 'Amount ($)'
    g.x_axis_label = 'Date'

    g.show_labels_for_bar_values = true

    g.label_rotation = -45

    g.marker_font_size = 14
    g.legend_font_size = 12
    g.hide_legend = true

    g.write("tmp/monthly_report_#{year}.png")
  end

  desc 'Plot option open interest for a given symbol, expiration date, and strike range'
  task :plot_open_interest, %i[
    symbol expiration_date
    min_strike max_strike
    contract_type
  ] => :environment do |_t, args|
    symbol = if args.symbol
               args.symbol
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

    strikes = options.map(&:strike)
    open_interests = options.map(&:open_interest)

    g = Gruff::Bar.new(800)
    g.title = "Open Interest for #{symbol} #{contract_type}s - Exp: #{expiration_date}"
    g.title_font_size = 20

    g.theme = {
      colors: contract_type == 'CALL' ? ['#006400'] : ['#DC143C'],
      marker_color: '#666666',
      font_color: '#333333',
      background_colors: %w[#ffffff #ffffff]
    }

    g.data(:open_interest, open_interests)
    g.labels = strikes.each_with_index.map { |strike, i| [i, strike.to_s] }.to_h

    g.hide_line_markers = false

    g.y_axis_label = 'Open Interest'
    g.x_axis_label = 'Strike Price'

    g.show_labels_for_bar_values = true

    g.label_rotation = -45

    g.marker_font_size = 14
    g.legend_font_size = 12
    g.hide_legend = true

    FileUtils.mkdir_p('tmp')

    output_path = "tmp/#{symbol}_#{contract_type.downcase}_open_interest_#{expiration_date}.png"
    g.write(output_path)

    puts "Open interest plot created at #{output_path}"

    puts "\nOpen Interest Summary:"
    puts "-" * 50
    puts "Strike | Open Interest"
    puts "-" * 50
    options.each do |opt|
      puts "#{opt.strike.to_s.ljust(6)} | #{opt.open_interest}"
    end
  end

  desc 'Print Open Orders'
  task :print_open_orders => :environment do |_t, args|
    orders = schwab_client.account_orders(
      status: 'PENDING_ACTIVATION',
      from_date: Date.today - 1,
      to_date: Date.today + 1
    )

    binding.pry
  end

  desc 'Print Trades'
  task :print_trades, [:start_days, :end_days] => :environment do |_t, args|
    # TEST: March 2025 be rake "schwab:print_trades[85,54]"
    from_date = Date.today - (args[:start_days] || 30).to_i
    to_date = Date.today - (args[:end_days] || 0).to_i
    orders = schwab_client.account_orders(
      from_date: from_date,
      to_date: to_date,
      status: 'FILLED'
    )

    transactions = schwab_client.transactions(
      from_date: from_date,
      to_date: to_date,
      transaction_types: ['TRADE']
    )

    order_details = build_order_details(orders, transactions)

    amount_dtls = order_details.map do |order_id, order_instruments|
      trade_date = order_instruments.first[1][:trade_dates].first

      amount = order_instruments.sum do |instrument_id, details|
        details[:net_amounts].sum
      end

      instrument_descriptions = order_instruments.map do |instrument_id, details|
        details[:description]
      end

      [trade_date, order_id, amount, instrument_descriptions]
    end.sort_by { |trade_date, _order_id, _amount| trade_date }

    amount_dtls.each do |trade_date, order_id, amount, descriptions|
      puts "Trade Date: #{trade_date.strftime('%m-%d-%Y')}, Order ID: #{order_id}, Net Amount: #{amount.round(2)}"
      descriptions.each do |description|
        puts "\tDescription: #{description}"
      end
      puts ""
    end

    total = amount_dtls.sum { |_, _, amount| amount }.round(2)
    puts "\n############\nTotal Amount: #{total}"
    binding.pry
  end

  desc 'Print Trade Status'
  task :trade_statuses, [:order_id] => :environment do |_t, args|
    order = schwab_client.get_order(args[:order_id])

    if order.nil?
      puts "Order with ID #{args[:order_id]} not found."
      exit
    end

    from_date = order.close_time.change({ hour: 0, min: 0, sec: 0 })
    to_date = order.close_time.change({ hour: 23, min: 59, sec: 59 })

    transactions = schwab_client.transactions(
      from_date: from_date,
      to_date: to_date,
      transaction_types: ['TRADE'],
    )

    order_legs = order.order_leg_collection.map do |leg|
      {
        instruction: leg.instruction,
        put_call: leg.instrument.put_call,
        symbol: leg.instrument.symbol,
        underlying_symbol: leg.instrument.underlying_symbol,
        description: leg.instrument.description,
        position_effect: leg.position_effect,
        quantity: leg.quantity,
        debit_credit: 0.0
      }
    end

    order_transactions = transactions.select { |t| t.order_id == order.order_id }
    if order_transactions.empty?
      puts "No transactions found for order ID #{order.order_id} on #{order.close_time.strftime('%m-%d-%Y')}"
      exit
    end

    order_transactions.each do |ot|
      opt_ti = ot.transfer_items.find { |ti| ti.instrument.asset_type == "OPTION" }
      order_leg = order_legs.find { |ol| ol[:symbol] == opt_ti.instrument.symbol }
      order_leg[:net_amount] = ot.net_amount
    end

    symbols = order_legs.select { |ol| ol[:position_effect] == "OPENING" }.map do |leg|
      leg[:symbol]
    end

    quotes = schwab_client.quotes(symbols)

    quotes.each do |quote|
      order_leg = order_legs.find { |ol| ol[:symbol] == quote.symbol }

      quantity = order_leg[:quantity]

      if order_leg[:instruction] == "SELL_TO_OPEN"
        order_leg[:mark] = quote.mark
        order_leg[:debit_credit] = -quote.mark * quantity * 100
      elsif order_leg[:instruction] == "BUY_TO_OPEN"
        order_leg[:mark] = quote.mark
        order_leg[:debit_credit] = quote.mark * quantity * 100
      end
    end

    order_net_amount = order_legs.sum { |ol| ol[:net_amount] }
    curr_credit_debit = order_legs.sum { |ol| ol[:debit_credit] }

    puts "Order ID: #{order.order_id}"
    puts "Order Net Amount: #{order_net_amount.round(2)}"
    puts "Current Credit/Debit: #{curr_credit_debit.round(2)}"
    # puts "Position progress: #{exit_progress(order_net_amount, curr_credit_debit).round(2)}%"
  end
end

def monthly_totals(schwab_client, year)
  first_and_last_dates_of_month(year).map do |first_date, last_date|
    orders = schwab_client.account_orders(
      from_date: first_date,
      to_date: last_date,
      status: 'FILLED'
    )

    transactions = schwab_client.transactions(
      from_date: first_date,
      to_date: last_date,
      transaction_types: ['TRADE']
    )

    order_details = build_order_details(orders, transactions)

    total_amount = order_details.sum do |_, order_instruments|
      order_instruments.sum do |_, details|
        details[:net_amounts].sum
      end
    end

    [first_date, total_amount]
  end
end

def first_and_last_dates_of_month(year)
  (1..12).map do |month|
    first_date = Date.new(year, month, 1)
    last_date = Date.new(year, month, -1) + 1
    [first_date, last_date]
  end
end

def build_order_details(orders, transactions)
  orders.map do |order|
    filled_quantity = order.filled_quantity
    order_instruments = order.order_leg_collection.map do |leg|
      [
        leg.instrument.instrument_id,
        {
          order_id: order.order_id,
          instrument_id: leg.instrument.instrument_id,
          description: leg.instrument.description,
          quantity: leg.quantity,
          put_call: leg.instrument.put_call,
          position_effect: leg.position_effect,
          costs: [],
          fees_and_commissions: [],
          trade_dates: [],
          net_amounts: [],
        }
      ]
    end.to_h

    transactions.select { |t| t.order_id == order.order_id }.each do |t|
      fees_and_commissions = t.transfer_items.select { |ti| !ti.fee_type.nil? }
      fees_and_commissions_sum = fees_and_commissions.map(&:cost).sum

      asset = t.transfer_items.find { |ti| ti.instrument.asset_type == "OPTION" }

      next unless asset

      order_instruments[asset.instrument.instrument_id][:costs] << asset.cost
      order_instruments[asset.instrument.instrument_id][:fees_and_commissions] << fees_and_commissions_sum
      order_instruments[asset.instrument.instrument_id][:trade_dates] << DateTime.parse(t.trade_date)
      order_instruments[asset.instrument.instrument_id][:net_amounts] << t.net_amount
    end

    [order.order_id, order_instruments]
  end.to_h
end

def trade_finder(trade_type, underlying, end_date, short_delta, max_spread, min_credit, min_open_interest,
                 dist_from_strike, quantity, settlement_type)
  case trade_type
  when 'iron_condor'
    Platypi::IronCondorFinder.new(
      underlying_symbol: underlying,
      expiration_date: end_date,
      short_delta: short_delta,
      max_spread: max_spread,
      min_credit: min_credit,
      min_open_interest: min_open_interest,
      dist_from_strike: dist_from_strike,
      quantity: quantity,
      settlement_type: settlement_type
    )
  when 'call_spread'
    Platypi::CallSpreadFinder.new(
      underlying_symbol: underlying,
      expiration_date: end_date,
      short_delta: short_delta,
      max_spread: max_spread,
      min_credit: min_credit,
      min_open_interest: min_open_interest,
      dist_from_strike: dist_from_strike,
      quantity: quantity,
      settlement_type: settlement_type
    )
  when 'put_spread'
    Platypi::PutSpreadFinder.new(
      underlying_symbol: underlying,
      expiration_date: end_date,
      short_delta: short_delta,
      max_spread: max_spread,
      min_credit: min_credit,
      min_open_interest: min_open_interest,
      dist_from_strike: dist_from_strike,
      quantity: quantity,
      settlement_type: settlement_type
    )
  else
    raise ArgumentError, "Invalid trade type: #{trade_type}"
  end
end
