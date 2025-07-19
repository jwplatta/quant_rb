require 'csv'
require 'fileutils'

module OptionsTrader
  module Exports
    class AccountOrders
      def initialize(schwab_client)
        @schwab_client = schwab_client
      end

      def export(from_date:, to_date:, account_name:)
        orders = @schwab_client.account_orders(
          from_date: from_date,
          to_date: to_date,
          status: 'FILLED'
        )

        transactions = @schwab_client.transactions(
          from_date: from_date,
          to_date: to_date,
          transaction_types: ['TRADE']
        )

        order_details = build_order_details(orders, transactions)

        FileUtils.mkdir_p('tmp')

        filename = "account_orders_#{account_name}_#{from_date.strftime('%Y%m%d')}_#{to_date.strftime('%Y%m%d')}.csv"
        filepath = File.join('tmp', filename)

        CSV.open(filepath, 'w', write_headers: true, headers: csv_headers) do |csv|
          order_details.each do |order_id, order_instruments|
            trade_date = order_instruments.first[1][:trade_dates].first

            order_net_amount = order_instruments.sum do |instrument_id, details|
              details[:net_amounts].sum
            end

            order_instruments.each do |instrument_id, details|
              details[:net_amounts].each_with_index do |net_amount, index|
                csv << [
                  order_id,
                  details[:trade_dates][index]&.strftime('%Y-%m-%d'),
                  details[:description],
                  details[:quantity],
                  details[:put_call],
                  details[:position_effect],
                  details[:costs][index] || 0,
                  details[:fees_and_commissions][index] || 0,
                  net_amount,
                  order_net_amount.round(2)
                ]
              end
            end
          end
        end

        filepath
      end

      private

      def csv_headers
        [
          'Order ID',
          'Trade Date',
          'Description',
          'Quantity',
          'Put/Call',
          'Position Effect',
          'Cost',
          'Fees & Commissions',
          'Net Amount',
          'Order Net Amount'
        ]
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
    end
  end
end
