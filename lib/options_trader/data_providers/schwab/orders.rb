require_relative 'base'

module OptionsTrader
  module DataProviders
    module Schwab
      class Orders < Base
        def initialize(account_name:)
          super()

          validate_account_name(account_name)
          @account_name = account_name
        end

        attr_reader :account_name

        def account(fields: nil)
          handle_api_errors("get_account") do
            client.get_account(account_name: account_name, fields: fields)
          end
        end

        def transactions(from_date: nil, to_date: nil, transaction_types: nil, symbol: nil)
          kwargs = {}
          kwargs[:start_date] = from_date if from_date
          kwargs[:end_date] = to_date if to_date
          kwargs[:transaction_types] = transaction_types if transaction_types
          kwargs[:symbol] = symbol if symbol

          handle_api_errors("get_transactions") do
            client.get_transactions(account_name: account_name, **kwargs)
          end
        end

        def transaction(activity_id: nil)
          handle_api_errors("get_transaction") do
            client.get_transaction(activity_id, account_name: account_name)
          end
        end

        def get_order(order_id)
          handle_api_errors("get_order") do
            client.get_order(order_id, account_name: account_name)
          end
        end

        def account_orders(from_date: nil, to_date: Date.today, status: 'FILLED')
          handle_api_errors("get_account_orders") do
            client.get_account_orders(
              account_name: account_name,
              from_entered_datetime: from_date,
              to_entered_datetime: to_date,
              status: status
            )
          end
        end

        def get_last_order(from_entered_datetime: DateTime.now)
          # NOTE: might want to send a few different requests with different statuses
          # like WORKING, PENDING_ACTIVATION, etc. to be more robust
          handle_api_errors("get_account_orders") do
            client.get_account_orders(
              account_name: account_name,
              status: SchwabRb::Order::Statuses::PENDING_ACTIVATION,
              from_entered_datetime: from_entered_datetime,
              to_entered_datetime: DateTime.now + 1,
            ).then do |orders|
              orders.first
            end
          end
        end

        def preview_order(order_instruction: :open, **strategy_kwargs)
          build_order(order_instruction: order_instruction, **strategy_kwargs).then do |order|
            handle_api_errors("preview_order") do
              client.preview_order(order, account_name: account_name)
            end
          end
        end

        def place_order(order_instruction: :open, **strategy_kwargs)
          # NOTE: Schwab API does not return the order id after placing the order.
          # Instead, we need to fetch the latest order after placing it.
          start = DateTime.now

          build_order(order_instruction: order_instruction, **strategy_kwargs).then do |order|
            handle_api_errors("place_order") do
              client.place_order(order, account_name: account_name).then do |resp|
                get_last_order(from_entered_datetime: start) if resp.status == 201
              end
            end
          end
        end

        def replace_order(order_id, order_instruction: :open, **strategy_kwargs)
          start = DateTime.now
          build_order(order_instruction: order_instruction, **strategy_kwargs).then do |order|
            handle_api_errors("replace_order") do
              client.replace_order(order_id, order, account_name: account_name).then do |resp|
                get_last_order(from_entered_datetime: start) if resp.status == 201
              end
            end
          end
        end

        def cancel_order(order_id)
          handle_api_errors("cancel_order") do
            client.cancel_order(order_id, account_name: account_name).then do |resp|
              resp.status == 200
            end
          end
        end

        def build_order(credit_debit: :credit, **strategy_kwargs)
          SchwabRb::Orders::OrderFactory.build(
            credit_debit: credit_debit,
            **strategy_kwargs
          )
        end

        private

        def validate_account_name(account_name)
          raise ArgumentError, "Invalid account name" unless client.available_account_names.include?(account_name)
        end
      end
    end
  end
end
