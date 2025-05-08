require "pry"
require "dotenv"
require "json"
require "csv"
require "schwab_rb"
require "date"
require_relative "../../mixins/schwab/data_objects/position"
require_relative "../../mixins/schwab/data_objects/account"
require_relative "../../mixins/schwab/data_objects/transaction"
require_relative "../../mixins/schwab/data_objects/order"
require_relative "../../mixins/schwab/data_objects/quote"

Dotenv.load

Trade = Struct.new(
  :opening,
  :closing,
)

def client
  @client ||= SchwabRb::Auth.init_client_easy(
    ENV["SCHWAB_API_KEY"],
    ENV["SCHWAB_APP_SECRET"],
    ENV["APP_CALLBACK_URL"],
    ENV["TOKEN_PATH"]
  )
end

namespace :schwab do
  desc "Refresh Schwab token"
  task :refresh_token do
    script_path = File.join(Dir.pwd, 'bin', 'refresh_token.rb')

    sh "ruby #{script_path}"

    puts "Token refreshed"
  end

  desc "Get Quote"
  task :get_quote, [:symbol] => :environment do |t, args|
    symbol = args[:symbol]
    quote = client.get_quote(symbol).then do |resp|
      DataObjects::QuoteFactory.build(
        JSON.parse(resp.body, symbolize_names: true)
      )
    end
    puts quote.to_h
  end

  desc "Write positions to CSV"
  task :positions do
    accounts_resp = JSON.parse(client.get_account_numbers.body)
    account_hash = accounts_resp.first['hashValue']
    account_resp = client.get_account(account_hash, fields: 'positions')
    account = JSON.parse(account_resp.body, symbolize_names: true).then do |acct_raw|
      DataObjects::Account.build(acct_raw)
    end

    account.positions.each do |position|
      puts position.to_h
    end
  end

  task :filled_orders do
    accounts_resp = JSON.parse(client.get_account_numbers.body)
    account_hash = accounts_resp.first['hashValue']
    orders_resp = client.get_account_orders(
      account_hash,
      from_entered_datetime: Date.new(2025, 1, 1),
      # to_entered_datetime: Date.new(2025, 1, 30),
      status: "FILLED"
    )
    filled_orders = JSON.parse(orders_resp.body, symbolize_names: true).then do |orders|
      orders.map { |o| DataObjects::Order.build(o) }
    end

    binding.pry
  end

  desc "Write transactions to CSV"
  task :transactions do
    accounts_resp = JSON.parse(client.get_account_numbers.body)
    account_hash = accounts_resp.first['hashValue']
    transactions_resp = client.get_transactions(
      account_hash,
      start_date: Date.new(2025, 1, 1)
    )
    rows = JSON.parse(transactions_resp.body, symbolize_names: true).then do |transactions|
      transactions.map do |t|
        DataObjects::Transaction.build(t)
      end
    end.select { |t| t.trade? }.map do |transaction|
      option = transaction.transfer_items.find { |ti| ti.instrument.option? }
      fees = transaction.transfer_items.select(&:fee?).sum(&:cost)
      commission = transaction.transfer_items.select(&:commission?).sum(&:cost)

      # order = client.get_order(transaction.order_id, account_hash).then do |resp|
      #   DataObjects::Order.build(
      #     JSON.parse(resp.body, symbolize_names: true)
      #   )
      # end
      # puts order.inspect

      if option.underlying_symbol == "TSLA"
        [
          transaction.order_id,
          transaction.position_id,
          transaction.activity_id,
          option.underlying_symbol,
          option.symbol,
          option.description,
          option.put_call,
          transaction.trade_date,
          option.position_effect,
          option.amount,
          fees,
          commission,
          option.cost,
          transaction.net_amount,
        ]
      end
    end.compact!.sort_by { |row| [row[4], row[6]] }
    binding.pry

    # closing_trades = rows.select { |row| row[7] == "CLOSING" }
    # opening_trades = rows.select { |row| row[7] == "OPENING" }
    # opening_trades_with_closing_trades = opening_trades.select do |opening_trade|
    #   closing_trades.any? { |closing_trade| closing_trade[1] == opening_trade[1] }
    # end
    # opening_trades_without_closing_trades = opening_trades.select do |opening_trade|
    #   closing_trades.none? { |closing_trade| closing_trade[1] == opening_trade[1] }
    # end
    rows.compact!

    headers = [
      "order",
      "position",
      "activity",
      "underlying",
      "symbol",
      "description",
      "put_call",
      "trade_date",
      "position_effect",
      "quantity",
      "fees",
      "commission",
      "cost",
      "net_amount",
    ]
    CSV.open("all_trades.csv", "w", write_headers: true, headers: headers) do |csv|
      rows.each do |row|
        csv << row
      end
    end
  end

  def account_hash
    @account_hash ||= JSON.parse(client.get_account_numbers.body).first["hashValue"]
  end
end
