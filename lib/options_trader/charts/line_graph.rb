# frozen_string_literal: true

module OptionsTrader
  module Charts
    class LineGraph < ChartBase
      def initialize(width: 1000, height: 700)
        super(width: width, height: height)
      end

      def generate(data_series, title: "Line Graph", x_axis_label: "X Axis", y_axis_label: "Y Axis",
                   min_x: nil, max_x: nil, min_y: nil, max_y: nil, vertical_line: nil,
                   vertical_line_label: nil, output_filename: nil)
        raise ArgumentError, "Data series cannot be empty" if data_series.nil? || data_series.empty?

        chart = create_line_chart(title)
        x_values = configure_chart_data(chart, data_series, min_x, max_x)
        configure_chart_options(chart, x_axis_label, y_axis_label, min_y, max_y)

        # Add vertical line if specified
        if vertical_line
          add_vertical_line(chart, vertical_line, x_values, vertical_line_label)
        end

        filename = output_filename || generate_filename(title)
        filepath = File.join(output_dir, filename)
        chart.write(filepath)

        filepath
      end

      private

      def create_line_chart(title)
        chart = Gruff::Line.new(width)
        chart.title = title
        chart.title_font_size = 18
        chart.theme = {
          colors: ['#0066CC', '#CC0000', '#00CC66', '#CC6600', '#6600CC'], # Multiple colors for series
          marker_color: '#666666',
          font_color: '#333333',
          background_colors: ['#ffffff', '#ffffff']
        }
        chart
      end

      def configure_chart_data(chart, data_series, min_x, max_x)
        # Handle both single series and multiple series
        if data_series.first.is_a?(Hash) && data_series.first.key?(:name)
          # Multiple named series: [{name: "Series 1", data: [[x1,y1], [x2,y2]]}, ...]
          data_series.each do |series|
            series_data = series[:data].sort_by(&:first) # Sort by x values
            y_values = series_data.map(&:last)
            chart.data(series[:name], y_values)
          end

          # Use x values from first series for labels
          x_values = data_series.first[:data].sort_by(&:first).map(&:first)
        else
          # Single series: [[x1,y1], [x2,y2], ...] or named single series
          if data_series.is_a?(Hash) && data_series.key?(:name)
            series_data = data_series[:data].sort_by(&:first)
            series_name = data_series[:name]
          else
            series_data = data_series.sort_by(&:first)
            series_name = "Data"
          end

          y_values = series_data.map(&:last)
          x_values = series_data.map(&:first)
          chart.data(series_name, y_values)
        end

        # Filter x_values if range specified
        if min_x || max_x
          filtered_indices = x_values.each_with_index.select do |x_val, idx|
            (min_x.nil? || x_val >= min_x) && (max_x.nil? || x_val <= max_x)
          end.map(&:last)
          x_values = filtered_indices.map { |i| x_values[i] }
        end

        # Create labels - show every nth value to avoid crowding
        labels = {}
        if x_values.length > 0
          label_interval = [x_values.length / 10, 1].max
          x_values.each_with_index do |x_val, index|
            if index % label_interval == 0 || index == x_values.length - 1
              labels[index] = format_label(x_val)
            end
          end
        end
        chart.labels = labels

        # Return x_values for vertical line calculations
        x_values
      end

      def configure_chart_options(chart, x_axis_label, y_axis_label, min_y, max_y)
        chart.hide_legend = false
        chart.legend_font_size = 14
        chart.marker_font_size = 12
        chart.y_axis_label = y_axis_label
        chart.x_axis_label = x_axis_label
        chart.line_width = 2
        chart.hide_dots = false
        chart.dot_radius = 1

        # Set y-axis range if specified
        chart.minimum_value = min_y if min_y
        chart.maximum_value = max_y if max_y
      end

      def format_label(value)
        if value.is_a?(Numeric)
          if value == value.to_i
            value.to_i.to_s
          else
            "%.1f" % value
          end
        else
          value.to_s
        end
      end

      def add_vertical_line(chart, vertical_line_x, x_values, label)
        return if x_values.empty?

        # Find the closest x index to our vertical line position
        closest_index = x_values.each_with_index.min_by { |x_val, idx| (x_val - vertical_line_x).abs }.last

        # Create a vertical line by adding a data series with only one point
        # We'll use a series that spans the full y range
        y_min = chart.minimum_value || 0
        y_max = chart.maximum_value || 1

        # Create an array of nil values with a single point at the vertical line position
        vertical_data = Array.new(x_values.length, nil)
        vertical_data[closest_index] = y_max

        # Add the vertical line as a data series
        line_label = label || "Spot Price"
        chart.data(line_label, vertical_data)

        # We'll also add a second invisible series to ensure the line extends to the bottom
        vertical_data_bottom = Array.new(x_values.length, nil)
        vertical_data_bottom[closest_index] = y_min
        chart.data("#{line_label} (bottom)", vertical_data_bottom)
      end

      def generate_filename(title)
        timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
        safe_title = title.downcase.gsub(/[^a-z0-9]/, '_').gsub(/_+/, '_').strip('_')
        "line_graph_#{safe_title}_#{timestamp}.png"
      end
    end
  end
end
