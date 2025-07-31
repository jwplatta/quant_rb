require 'csv'
require 'fileutils'

module OptionsTrader
  module Exports
    class TransactionsByOrder
      class << self
        def export(schwab_client:, out_dir: 'tmp', from_date:, to_date:, account_names: [])
          TransactionsByOrder.new(
            schwab_client: schwab_client,
            out_dir: out_dir
          ).export(
            from_date: from_date,
            to_date: to_date,
            account_names: account_names
          )
        end
      end

      COLUMNS_HEADERS = [
        'Trade Date',
        'Order ID / Symbol',
        'Quantity',
        'Description',
        'Put/Call',
        'Position Effect',
        'Credit/Debit',
        'Fees & Commissions',
        'Net Amount'
      ].freeze

      def initialize(schwab_client:, out_dir: 'tmp')
        @schwab_client = schwab_client
        raise ArgumentError, "Output directory does not exist: #{out_dir}" unless Dir.exist?(out_dir)
        @out_dir = out_dir
      end

      attr_reader :out_dir, :schwab_client

      def export(from_date:, to_date:, account_names: [])
        return nil if account_names.empty?

        account_names.map do |account_name|
          schwab_client.set_account(account_name)
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
          to_csv(orders, order_details, account_name, to_date)
        end
      end

      def to_csv(orders, order_details, account_name, to_date)
        filename = "#{account_name}_#{to_date.strftime('%Y%m%d')}.csv"
        filepath = File.join(out_dir, filename)

        CSV.open(filepath, 'w', write_headers: true, headers: COLUMNS_HEADERS) do |csv|
          orders.each do |order|
            order_id = order.order_id
            dtls = order_details[order_id] || {}

            order_net_amount = dtls.sum { |_, v| v[:net_amounts] }
            csv << [
              order.close_time.strftime('%Y-%m-%d'),
              "ORDER #{order_id}",
              order.filled_quantity, # Quantity
              '', # Put/Call
              '', # Position Effect
              '', # Cost
              '', # Fees & Commissions
              '', # Net Amount
              order_net_amount.round(2)
            ]
            next if dtls.empty?

            dtls.each do |instrument_id, dtl|
              position_id = dtl[:position_id].uniq

              if position_id.size > 1
                raise "Multiple position IDs found for instrument #{dtl[:symbol]} in order #{order_id}: #{position_id.join(', ')}"
              end

              csv << [
                position_id.first,
                dtl[:symbol],
                dtl[:quantity],
                dtl[:description],
                dtl[:put_call],
                dtl[:position_effect],
                dtl[:credit_debits].round(2),
                dtl[:fees_and_commissions].round(2),
                dtl[:net_amounts].round(2),
              ]
            end

            csv << ['', '', '', '', '', '', '', '', '', '']
          end
        end

        filepath
      end

      private

      def build_order_details(orders, transactions)
        orders.map do |order|
          order_instruments = order.order_leg_collection.map do |leg|
            [
              leg.instrument_id,
              {
                symbol: leg.symbol,
                description: leg.instrument.description,
                quantity: leg.quantity,
                put_call: leg.put_call,
                position_effect: leg.position_effect,
                position_id: [],
                net_amounts: 0,
                credit_debits: 0,
                fees_and_commissions: 0,
              }
            ]
          end.to_h

          order_transactions = transactions.select { |t| t.order_id == order.order_id }

          order_transactions.each do |t|
            fees_and_commissions = t.fees.sum + t.commissions.sum

            order_instruments[t.asset_instrument_id][:position_id] << t.position_id
            order_instruments[t.asset_instrument_id][:credit_debits] += t.credit_debits.sum
            order_instruments[t.asset_instrument_id][:fees_and_commissions] += fees_and_commissions
            order_instruments[t.asset_instrument_id][:net_amounts] += t.net_amount
          end

          [order.order_id, order_instruments]
        end.to_h
      end
    end
  end
end
