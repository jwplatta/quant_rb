require "schwab_rb"
require "dotenv"
require "pry"
require_relative "data_objects/quote"
require_relative "data_objects/option_chain"
require_relative "data_objects/account"
require_relative "data_objects/transaction"
require_relative "data_objects/order"
require_relative "data_objects/order_preview"

Dotenv.load

module Schwab
  @client = nil
  @account_hash = nil

  def self.client
    return @client if @client

    token_path = ENV["TOKEN_PATH"]
    @client = SchwabRb::Auth.init_client_easy(
      ENV["SCHWAB_API_KEY"],
      ENV["SCHWAB_APP_SECRET"],
      ENV["APP_CALLBACK_URL"],
      token_path
    )
  end

  def self.reset_client
    @client = nil
  end

  def self.quote(symbol)
    client.get_quote(symbol).then do |resp|
      JSON.parse(resp.body, symbolize_names: true).then do |data|
        DataObjects::QuoteFactory.build(data)
      end
    end
  end

  def self.option_chain(
    symbol,
    contract_type: "ALL",
    strike_range: "OTM",
    from_date: nil,
    to_date: nil,
    days_to_expiration: nil
  )
    kwargs = {
      contract_type: contract_type,
      strike_range: strike_range
    }

    if days_to_expiration
      kwargs[:days_to_expiration] = days_to_expiration
    else
      kwargs[:to_date] = to_date
    end

    client.get_option_chain(
      symbol,
      **kwargs
    ).then do |resp|
      JSON.parse(resp.body, symbolize_names: true).then do |data|
        DataObjects::OptionChain.build(data)
      end
    end
  end

  def self.account(fields: nil)
    client.get_account(account_hash, fields: fields).then do |resp|
      JSON.parse(resp.body, symbolize_names: true).then do |data|
        DataObjects::Account.build(data)
      end
    end
  end

  def self.transactions(start_date: nil, end_date: nil, transaction_types: nil, symbol: nil)
    kwargs = {}
    kwargs[:start_date] = start_date if start_date
    kwargs[:end_date] = end_date if end_date
    kwargs[:transaction_types] = transaction_types if transaction_types
    kwargs[:symbol] = symbol if symbol

    client.get_transactions(account_hash, **kwargs).then do |resp|
      JSON.parse(resp.body, symbolize_names: true).then do |transactions|
        transactions.map { |t| DataObjects::Transaction.build(t) }
      end
    end
  end

  def self.account_orders(from_date, to_date, status)
    client.get_account_orders(
      account_hash,
      from_entered_datetime: from_date,
      to_entered_datetime: to_date,
      status: status
    ).then do |resp|
      JSON.parse(resp.body, symbolize_names: true)
    end.then do |orders|
      orders.map { |o| DataObjects::Order.build(o) }
    end
  end

  def self.account_hash
    return @account_hash if @account_hash

    @account_hash = client.get_account_numbers.then do |resp|
      JSON.parse(resp.body).first['hashValue']
    end
  end

  def self.preview_order(order)
    client.preview_order(account_hash, order).then do |resp|
      JSON.parse(resp.body, symbolize_names: true)
    end.then do |data|
      DataObjects::OrderPreview.build(data)
    end
  end

  def self.place_order(order)
    client.place_order(account_hash, order).then do |resp|
      JSON.parse(resp.body, symbolize_names: true)
    end.then do |data|
      DataObjects::Order.build(data)
    end
  end
end
