# frozen_string_literal: true

module OptionsTrader
  module Charts
    class MonthlyProgress < ChartBase
      def initialize(schwab_client, account_names: [])
        @schwab_client = schwab_client
        @account_names = Array(account_names)
        super()
      end

      def generate(year:, account_name: nil)
        accounts_to_process = account_name ? [account_name] : @account_names

        raise ArgumentError, "No accounts specified for monthly progress chart" if accounts_to_process.empty?

        if accounts_to_process.size == 1
          data = monthly_totals_for_account(year, accounts_to_process.first)
          account_display_name = accounts_to_process.first
        else
          data = aggregated_monthly_totals(year, accounts_to_process)
          account_display_name = "Combined (#{accounts_to_process.join(', ')})"
        end

        validate_data!(data)

        dates = data.map { |entry| entry.first.strftime("%b") }
        amounts = data.map { |entry| entry[1] }

        chart = create_chart(year, account_display_name)
        configure_data(chart, amounts, dates)
        configure_chart_options(chart)

        filename = generate_filename(year, accounts_to_process)
        filepath = File.join(output_dir, filename)
        chart.write(filepath)

        filepath
      end

      private

      def generate_filename(year, account_names)
        if account_names.size == 1
          "monthly_report_#{year}_#{account_names.first}.png"
        else
          "monthly_report_#{year}_combined_#{account_names.join('_')}.png"
        end
      end

      def aggregated_monthly_totals(year, account_names)
        account_totals = account_names.map do |account_name|
          monthly_totals_for_account(year, account_name)
        end

        first_and_last_dates_of_month(year).map.with_index do |(first_date, _), month_index|
          total_amount = account_totals.sum do |account_monthly_data|
            # Get the amount for this month from each account's data
            account_monthly_data[month_index][1] # [date, amount] - we want the amount
          end

          [first_date, total_amount]
        end
      end

      def monthly_totals_for_account(year, account_name)
        @schwab_client.set_account(account_name)

        monthly_totals(year)
      end

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

      def create_chart(year, account_display_name)
        chart = Gruff::Bar.new(width)
        chart.title = "Monthly Progress for #{year} (#{account_display_name})"
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

          replaced_orders = @schwab_client.account_orders(
            from_date: first_date,
            to_date: last_date,
            status: 'REPLACED'
          )

          orders += replaced_orders

          transactions = @schwab_client.transactions(
            from_date: first_date,
            to_date: last_date,
            transaction_types: ['TRADE']
          )

          order_details = build_order_details(orders, transactions)

          # total_amount = order_details.sum do |_, transaction_details_array|
          #   transaction_details_array.sum { |details| details[:net_amounts].sum }
          # end
          total_amount = order_details.values.sum

          [first_date, total_amount]
        end
      end

      def first_and_last_dates_of_month(year)
        (1..12).map do |month|
          first_date = Date.new(year, month, 1).to_datetime.change({ hour: 0, min: 0, sec: 0 })
          last_date = Date.new(year, month, -1).to_datetime.change({ hour: 23, min: 59, sec: 59 })
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

          order_total = transactions.select { |t| t.order_id == order.order_id }.sum do |t|
            asset = t.transfer_items.find { |ti| ti.instrument.asset_type == "OPTION" }
            if asset
              t.net_amount
            else
              0.0
            end

            # fees_and_commissions = t.transfer_items.select { |ti| !ti.fee_type.nil? }
            # fees_and_commissions_sum = fees_and_commissions.sum(&:cost)

            # order_instruments[asset.instrument.instrument_id][:costs] << asset.cost
            # order_instruments[asset.instrument.instrument_id][:fees_and_commissions] << fees_and_commissions_sum
            # order_instruments[asset.instrument.instrument_id][:trade_dates] << DateTime.parse(t.trade_date)
            # order_instruments[asset.instrument.instrument_id][:net_amounts] << t.net_amount
          end

          [order.order_id, order_total]
        end.to_h
      end
    end
  end
end
