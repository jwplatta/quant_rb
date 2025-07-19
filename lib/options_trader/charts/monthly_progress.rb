# frozen_string_literal: true

module OptionsTrader
  module Charts
    class MonthlyProgress < Base
      def initialize(schwab_client)
        @schwab_client = schwab_client
        super()
      end

      def generate(year:, account_name:)
        data = monthly_totals(year)
        validate_data!(data)

        dates = data.map { |entry| entry.first.strftime("%b") }
        amounts = data.map { |entry| entry[1] }

        chart = create_chart(year, account_name)
        configure_data(chart, amounts, dates)
        configure_chart_options(chart)

        filename = "monthly_report_#{year}_#{account_name}.png"
        filepath = File.join(output_dir, filename)
        chart.write(filepath)

        filepath
      end

      private

      def validate_data!(data)
        raise ArgumentError, "Data cannot be empty" if data.empty?

        data.each_with_index do |entry, index|
          unless entry.is_a?(Array) && entry.length == 2
            raise ArgumentError, "Entry at index #{index} must be an array with 2 elements [date, amount]"
          end

          unless entry[0].respond_to?(:strftime)
            raise ArgumentError, "First element at index #{index} must be a Date object"
          end

          unless entry[1].is_a?(Numeric)
            raise ArgumentError, "Second element at index #{index} must be numeric"
          end
        end
      end

      def create_chart(year, account_name)
        chart = Gruff::Bar.new(width)
        chart.title = "Monthly Progress for #{year} (#{account_name})"
        chart.title_font_size = 20
        chart.theme = default_theme
        chart
      end

      def configure_data(chart, amounts, dates)
        chart.data(:amounts, amounts)
        chart.labels = dates.each_with_index.to_h { |date, i| [i, date] }
      end

      def configure_chart_options(chart)
        configure_common_chart_options(chart)
        chart.y_axis_label = 'Amount ($)'
        chart.x_axis_label = 'Month'
      end

      def monthly_totals(year)
        first_and_last_dates_of_month(year).map do |first_date, last_date|
          orders = @schwab_client.account_orders(
            from_date: first_date,
            to_date: last_date,
            status: 'FILLED'
          )

          transactions = @schwab_client.transactions(
            from_date: first_date,
            to_date: last_date,
            transaction_types: ['TRADE']
          )

          order_details = build_order_details(orders, transactions)

          total_amount = order_details.sum do |_, transaction_details_array|
            transaction_details_array.sum { |details| details[:net_amounts].sum }
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

          transactions.select { |t| t.order_id == order.order_id }.map do |t|
            asset = t.transfer_items.find { |ti| ti.instrument.asset_type == "OPTION" }
            next unless asset

            fees_and_commissions = t.transfer_items.select { |ti| !ti.fee_type.nil? }
            fees_and_commissions_sum = fees_and_commissions.sum(&:cost)

            order_instruments[asset.instrument.instrument_id][:costs] << asset.cost
            order_instruments[asset.instrument.instrument_id][:fees_and_commissions] << fees_and_commissions_sum
            order_instruments[asset.instrument.instrument_id][:trade_dates] << DateTime.parse(t.trade_date)
            order_instruments[asset.instrument.instrument_id][:net_amounts] << t.net_amount
          end

          [order.order_id, order_instruments.map { |instrument_id, details| details }]
        end.to_h
      end
    end
  end
end
