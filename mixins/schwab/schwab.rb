# frozen_string_literal: true

require 'schwab_rb'
require 'dotenv'
require 'pry'
require_relative 'data_objects/quote'
require_relative 'data_objects/option_chain'
require_relative 'data_objects/account'
require_relative 'data_objects/transaction'
require_relative 'data_objects/order'
require_relative 'data_objects/order_preview'
require_relative 'orders/order_factory'

Dotenv.load

module Schwab
  def client
    return @client if @client

    token_path = ENV['TOKEN_PATH']
    @client = SchwabRb::Auth.init_client_easy(
      ENV['SCHWAB_API_KEY'],
      ENV['SCHWAB_APP_SECRET'],
      ENV['APP_CALLBACK_URL'],
      token_path
    )
  end

  def reset_client
    @client = nil
  end

  def quote(symbol)
    client.get_quote(symbol).then do |resp|
      parsed_data = JSON.parse(resp.body, symbolize_names: true)

      # The QuoteFactory expects data in the format: { symbol => quote_data }
      unless parsed_data.is_a?(Hash) && parsed_data.size == 1 && parsed_data.values.first.is_a?(Hash)
        raise "Unexpected quote data format: #{parsed_data.inspect}"
      end

      DataObjects::QuoteFactory.build(parsed_data)
    end
  end

  def quotes(symbols)
    client.get_quotes(symbols).then do |resp|
      parsed_data = JSON.parse(resp.body, symbolize_names: true)

      # REVIEW: The QuoteFactory expects data in the format: { symbol => quote_data }
      # and the Schwab API should return data in this format
      parsed_data.map do |symbol, quote_data|
        quote_hash = { symbol => quote_data }
        DataObjects::QuoteFactory.build(quote_hash)
      end
    end
  end

  def option_chain(
    symbol,
    contract_type: 'ALL',
    strike_range: 'OTM',
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
      kwargs[:from_date] = from_date if from_date
    end

    client.get_option_chain(
      symbol,
      **kwargs
    ).then do |resp|
      JSON.parse(resp.body, symbolize_names: true)
    end.then do |data|
      DataObjects::OptionChain.build(data)
    end
  end

  def account(fields: nil)
    client.get_account(account_hash, fields: fields).then do |resp|
      JSON.parse(resp.body, symbolize_names: true)
    end.then do |data|
      DataObjects::Account.build(data)
    end
  end

  def transactions(start_date: nil, end_date: nil, transaction_types: nil, symbol: nil)
    kwargs = {}
    kwargs[:start_date] = start_date if start_date
    kwargs[:end_date] = end_date if end_date
    kwargs[:transaction_types] = transaction_types if transaction_types
    kwargs[:symbol] = symbol if symbol

    client.get_transactions(account_hash, **kwargs).then do |resp|
      JSON.parse(resp.body, symbolize_names: true)
    end.then do |transactions|
      transactions.map { |t| DataObjects::Transaction.build(t) }
    end
  end

  def transaction(activity_id: nil)
    client.get_transaction(account_hash, activity_id).then do |resp|
      JSON.parse(resp.body, symbolize_names: true)
    end.then do |data|
      DataObjects::Transaction.build(data)
    end
  end

  def account_orders(from_date, to_date, status)
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

  def account_hash
    return @account_hash if @account_hash

    @account_hash = client.get_account_numbers.then do |resp|
      JSON.parse(resp.body).first['hashValue']
    end
  end

  def build_and_preview_order(trade, quantity: 1, order_instruction: :entry)
    build_order(trade, quantity: quantity, order_instruction: order_instruction).then do |order|
      preview_order(order)
    end
  end

  def build_and_place_order(trade, quantity: 1, order_instruction: :entry)
    build_order(trade, quantity: quantity, order_instruction: order_instruction).then do |order|
      place_order(order)
    end
  end

  def build_and_replace_order(order_id, trade, quantity: 1, order_instruction: :entry)
    build_order(trade, quantity: quantity, order_instruction: order_instruction).then do |order|
      replace_order(order_id, order)
    end
  end

  def build_order(trade, quantity: 1, order_instruction: :entry)
    OrderFactory.build(
      trade,
      quantity: quantity,
      order_instruction: order_instruction,
      account_number: ENV['SCHWAB_ACCOUNT_NUMBER']
    )
  end

  def preview_order(order)
    client.preview_order(account_hash, order).then do |resp|
      File.open('order_preview.json', 'w') { |f| f.write(resp.body) }

      JSON.parse(resp.body, symbolize_names: true)
    end.then do |data|
      DataObjects::OrderPreview.build(data)
    end
  end

  def get_latest_order(from_entered_datetime: DateTime.now)
    client.get_account_orders(
      account_hash,
      status: SchwabRb::Order::Statuses::PENDING_ACTIVATION,
      from_entered_datetime: from_entered_datetime,
      to_entered_datetime: DateTime.now + 1
    ).then do |orders|
      JSON.parse(orders.body, symbolize_names: true)
    end.then do |orders|
      DataObjects::Order.build(orders.first)
    end
  end

  def get_order(order_id)
    client.get_order(order_id, account_hash).then do |resp|
      JSON.parse(resp.body, symbolize_names: true)
    end.then do |data|
      DataObjects::Order.build(data)
    end
  end

  def place_order(order)
    start = DateTime.now
    client.place_order(account_hash, order).then do |resp|
      get_latest_order(from_entered_datetime: start) if resp.status == 201
    end
  end

  def replace_order(order_id, order)
    start = DateTime.now
    client.replace_order(account_hash, order_id, order).then do |resp|
      get_latest_order(from_entered_datetime: start) if resp.status == 201
    end
  end

  def cancel_order(order_id)
    client.cancel_order(order_id, account_hash).then do |resp|
      resp.status == 200
    end
  end
end
