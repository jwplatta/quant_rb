# frozen_string_literal: true

module OptionsTrader
  module Charts
    class CompareDeltas < ChartBase
      def initialize(width: 1000, height: 700)
        super(width: width, height: height)
      end

      def generate(actual_deltas, calculated_deltas, contract_type, expiry_date, output_filename: nil)
        raise ArgumentError, "Actual deltas cannot be empty" if actual_deltas.nil? || actual_deltas.empty?
        raise ArgumentError, "Calculated deltas cannot be empty" if calculated_deltas.nil? || calculated_deltas.empty?

        # Sort both arrays by strike for proper line plotting
        actual_sorted = actual_deltas.sort_by { |strike, _delta| strike }
        calculated_sorted = calculated_deltas.sort_by { |strike, _delta| strike }

        chart = create_line_chart(contract_type, expiry_date)
        configure_chart_data(chart, actual_sorted, calculated_sorted)
        configure_chart_options(chart)

        filename = output_filename || generate_filename(contract_type, expiry_date)
        filepath = File.join(output_dir, filename)
        chart.write(filepath)

        filepath
      end

      private

      def create_line_chart(contract_type, expiry_date)
        chart = Gruff::Line.new(width)
        chart.title = "Delta Comparison: #{contract_type} Options (#{expiry_date.strftime('%Y-%m-%d')})"
        chart.title_font_size = 18
        chart.theme = {
          colors: ['#0066CC', '#CC0000'], # Blue for actual, red for calculated
          marker_color: '#666666',
          font_color: '#333333',
          background_colors: ['#ffffff', '#ffffff']
        }
        chart
      end

      def configure_chart_data(chart, actual_data, calculated_data)
        # Extract deltas for plotting
        actual_deltas = actual_data.map(&:last)
        calculated_deltas = calculated_data.map(&:last)

        # Add the data series
        chart.data('Actual Deltas', actual_deltas)
        chart.data('Calculated Deltas', calculated_deltas)

        # Use actual strikes for x-axis labels (assuming they have more coverage)
        all_strikes = actual_data.map(&:first).uniq.sort

        # Create labels - show every nth strike to avoid crowding
        labels = {}
        label_interval = [all_strikes.length / 10, 1].max
        all_strikes.each_with_index do |strike, index|
          if index % label_interval == 0 || index == all_strikes.length - 1
            labels[index] = strike.to_i.to_s
          end
        end
        chart.labels = labels
      end

      def configure_chart_options(chart)
        chart.hide_legend = false
        chart.legend_font_size = 14
        chart.marker_font_size = 12
        chart.y_axis_label = 'Delta'
        chart.x_axis_label = 'Strike Price ($)'
        chart.line_width = 2
        chart.hide_dots = true
        chart.dot_radius = 2

        # Set y-axis range appropriate for deltas
        chart.minimum_value = -1.1
        chart.maximum_value = 1.1
      end

      def generate_filename(contract_type, expiry_date)
        timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
        "delta_comparison_#{contract_type.downcase}_#{expiry_date.strftime('%Y%m%d')}_#{timestamp}.png"
      end
    end
  end
end