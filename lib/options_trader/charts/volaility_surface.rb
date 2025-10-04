# frozen_string_literal: true

module OptionsTrader
  module Charts
    class VolatilitySurface < ChartBase
      def initialize(width: 1000, height: 700)
        super(width: width, height: height)
      end

      def generate(volatility_surface, spot_price, expiry_date, output_filename: nil)
        raise ArgumentError, "Volatility surface cannot be empty" if volatility_surface.nil? || volatility_surface.empty?

        surface_data = volatility_surface[expiry_date]
        raise ArgumentError, "No data for expiry #{expiry_date}" unless surface_data

        # Store for use in parity calculations
        @spot_price = spot_price
        @time_to_expiry = surface_data[:time_to_expiry]

        smile_data = surface_data[:smile]
        call_points = smile_data[:call_points] || {}
        put_points = smile_data[:put_points] || {}

        raise ArgumentError, "No volatility points found" if call_points.empty? && put_points.empty?

        call_data, put_data = separate_call_put_data(call_points, put_points)

        chart = create_line_chart(expiry_date, spot_price)
        configure_chart_data(chart, call_data, put_data)
        configure_chart_options(chart)

        filename = output_filename || generate_filename(expiry_date)
        filepath = File.join(output_dir, filename)
        chart.write(filepath)

        filepath
      end

      private

      def separate_call_put_data(call_points, put_points)
        # Fill in missing strikes using put-call parity
        filled_call_points, filled_put_points = fill_missing_strikes_with_parity(
          call_points, put_points, @spot_price, @time_to_expiry, 0.045
        )

        call_data = []
        put_data = []

        filled_call_points.each do |strike, vol_info|
          volatility_percent = vol_info[:volatility] * 100
          call_data << [strike, volatility_percent]
        end

        filled_put_points.each do |strike, vol_info|
          volatility_percent = vol_info[:volatility] * 100
          put_data << [strike, volatility_percent]
        end

        # Sort by strike for proper line plotting
        call_data.sort_by! { |strike, _vol| strike }
        put_data.sort_by! { |strike, _vol| strike }

        [call_data, put_data]
      end

      def convert_puts_to_calls(put_vol, spot, strike, time_to_expiry, rate)
        # Put-call parity: Call = Put + Spot - PV(Strike)
        # Since volatility should be the same for equivalent positions
        put_vol  # Volatility is the same for synthetic equivalents
      end

      def fill_missing_strikes_with_parity(call_points, put_points, spot, time_to_expiry, rate)
        filled_call_points = call_points.dup
        filled_put_points = put_points.dup

        # Get all unique strikes from both calls and puts
        all_strikes = (call_points.keys + put_points.keys).uniq

        all_strikes.each do |strike|
          # If we have a put but no call, create synthetic call
          if put_points[strike] && !call_points[strike]
            put_vol = put_points[strike][:volatility]
            call_vol = convert_puts_to_calls(put_vol, spot, strike, time_to_expiry, rate)

            filled_call_points[strike] = {
              volatility: call_vol,
              synthetic: true,
              moneyness: spot / strike,
              option_type: 'CALL'
            }
          end

          # If we have a call but no put, create synthetic put
          if call_points[strike] && !put_points[strike]
            call_vol = call_points[strike][:volatility]
            put_vol = call_vol  # Same volatility for synthetic equivalent

            filled_put_points[strike] = {
              volatility: put_vol,
              synthetic: true,
              moneyness: spot / strike,
              option_type: 'PUT'
            }
          end
        end

        [filled_call_points, filled_put_points]
      end

      def create_line_chart(expiry_date, spot_price)
        chart = Gruff::Line.new(width)
        chart.title = "Volatility Smile for #{expiry_date.strftime('%Y-%m-%d')} (Spot: $#{spot_price.round(2)})"
        chart.title_font_size = 18
        chart.theme = {
          colors: ['#0066CC', '#CC0000'], # Blue for calls, red for puts
          marker_color: '#666666',
          font_color: '#333333',
          background_colors: ['#ffffff', '#ffffff']
        }
        chart
      end

      def configure_chart_data(chart, call_data, put_data)
        unless call_data.empty?
          call_vols = call_data.map(&:last)
          chart.data('CALLS', call_vols)
        end

        unless put_data.empty?
          put_vols = put_data.map(&:last)
          chart.data('PUTS', put_vols)
        end

        # Use all unique strikes for x-axis labels
        all_strikes = (call_data.map(&:first) + put_data.map(&:first)).uniq.sort

        # Create labels - show every nth strike to avoid crowding
        labels = {}
        label_interval = [all_strikes.length / 8, 1].max
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
        chart.y_axis_label = 'Implied Volatility (%)'
        chart.x_axis_label = 'Strike Price ($)'
        chart.line_width = 1
        chart.hide_dots = true
        chart.dot_radius = 3
      end

      def generate_filename(expiry_date)
        timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
        "volatility_smile_#{expiry_date.strftime('%Y%m%d')}_#{timestamp}.png"
      end
    end
  end
end
