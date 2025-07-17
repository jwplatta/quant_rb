# frozen_string_literal: true

module OptionsTrader
  module Charts
    class MonthlyProgress < Base
      def generate(data, year:, account_name:)
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
    end
  end
end
