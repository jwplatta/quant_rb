# frozen_string_literal: true

require 'gruff'
require 'fileutils'

module OptionsTrader
  module Charts
    class ChartBase
      attr_reader :width, :height, :output_dir

      def initialize(width: 800, height: 600, output_dir: 'tmp')
        @width = width
        @height = height
        @output_dir = output_dir
        ensure_output_dir
      end

      private

      def ensure_output_dir
        FileUtils.mkdir_p(output_dir)
      end

      def default_theme
        {
          colors: %w[#006400 #DC143C #4169E1],
          marker_color: '#666666',
          font_color: '#333333',
          background_colors: %w[#ffffff #ffffff]
        }
      end

      def configure_common_chart_options(chart)
        chart.hide_line_markers = false
        chart.show_labels_for_bar_values = true
        chart.label_rotation = -45
        chart.marker_font_size = 14
        chart.legend_font_size = 12
        chart.hide_legend = true
      end
    end
  end
end
