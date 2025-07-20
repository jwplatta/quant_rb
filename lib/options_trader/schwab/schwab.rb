# frozen_string_literal: true

require 'schwab_rb'
require_relative 'orders/order_factory'
require_relative 'accounts'

module OptionsTrader
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

    def set_account(account_name)
      @account_name = account_name
      @current_account = nil
    end

    def current_account_name
      @account_name || raise("No account set. Call set_account(account_name) first.")
    end

    def current_account
      @current_account ||= Accounts.new(current_account_name)
    end

    def available_accounts
      Accounts.account_names
    end

    def account_exists?(account_name)
      Accounts.accounts.key?(account_name.to_s)
    end

    def switch_account(account_name)
      unless account_exists?(account_name)
        raise "Account '#{account_name}' not found. Available accounts: #{available_accounts.join(', ')}"
      end
      set_account(account_name)
    end

    def reset_client
      @client = nil
    end

    def quote(symbol)
      client.get_quote(symbol, return_data_objects: true)
    end

    def quotes(symbols)
      client.get_quotes(symbols, return_data_objects: true)
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
      end
    end

    def account(fields: nil)
      client.get_account(account_hash, fields: fields, return_data_objects: true)
    end

    def transactions(from_date: nil, to_date: nil, transaction_types: nil, symbol: nil)
      kwargs = {}
      kwargs[:start_date] = from_date if from_date
      kwargs[:end_date] = to_date if to_date
      kwargs[:transaction_types] = transaction_types if transaction_types
      kwargs[:symbol] = symbol if symbol

      client.get_transactions(account_hash, **kwargs).then do |resp|
        JSON.parse(resp.body, symbolize_names: true)
      end
    end

    def transaction(activity_id: nil)
      client.get_transaction(account_hash, activity_id).then do |resp|
        JSON.parse(resp.body, symbolize_names: true)
      end
    end

    def account_orders(from_date: nil, to_date: Date.today, status: 'FILLED')
      client.get_account_orders(
        account_hash,
        from_entered_datetime: from_date,
        to_entered_datetime: to_date,
        status: status
      ).then do |resp|
        JSON.parse(resp.body, symbolize_names: true)
      end
    end

    def account_hash
      current_account.account_hash(client)
    end

    def build_and_preview_order(order_instruction: :open, **strategy_kwargs)
      build_order(order_instruction: order_instruction, **strategy_kwargs).then do |order|
        preview_order(order)
      end
    end

    def build_and_place_order(order_instruction: :open, **strategy_kwargs)
      build_order(order_instruction: order_instruction, **strategy_kwargs).then do |order|
        place_order(order)
      end
    end

    def build_and_replace_order(order_id, order_instruction: :open, **strategy_kwargs)
      build_order(order_instruction: order_instruction, **strategy_kwargs).then do |order|
        replace_order(order_id, order)
      end
    end

    def build_order(order_instruction: :open, **strategy_kwargs)
      OrderFactory.build(
        order_instruction: order_instruction,
        account_number: current_account.account_number,
        **strategy_kwargs
      )
    end

    def preview_order(order)
      client.preview_order(account_hash, order).then do |resp|
        File.open('order_preview.json', 'w') { |f| f.write(resp.body) }

        JSON.parse(resp.body, symbolize_names: true)
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
        orders.first
      end
    end

    def get_order(order_id)
      client.get_order(order_id, account_hash).then do |resp|
        JSON.parse(resp.body, symbolize_names: true)
      end
    end

    def place_order(order)
      # NOTE: Schwab API does not return the order id after placing the order.
      # Instead, we need to fetch the latest order after placing it.
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
end
