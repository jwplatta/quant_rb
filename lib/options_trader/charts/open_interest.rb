# frozen_string_literal: true

module OptionsTrader
  module Charts
    class OpenInterest < ChartBase
      def generate(options, symbol:, contract_type:, expiration_date:)
        validate_inputs!(options, symbol, contract_type, expiration_date)

        sorted_options = options.sort_by(&:strike)
        strikes = sorted_options.map(&:strike)
        open_interests = sorted_options.map(&:open_interest)

        chart = create_chart(symbol, contract_type, expiration_date)
        configure_data(chart, open_interests, strikes)
        configure_chart_options(chart, contract_type)

        filename = "#{symbol}_#{contract_type.downcase}_open_interest_#{expiration_date}.png"
        filepath = File.join(output_dir, filename)
        chart.write(filepath)

        { filepath: filepath, options: sorted_options }
      end

      private

      def validate_inputs!(options, symbol, contract_type, expiration_date)
        raise ArgumentError, "Options cannot be empty" if options.empty?
        raise ArgumentError, "Symbol cannot be nil or empty" if symbol.nil? || symbol.empty?
        raise ArgumentError, "Contract type must be CALL or PUT" unless %w[CALL PUT].include?(contract_type)
        raise ArgumentError, "Expiration date cannot be nil" if expiration_date.nil?

        options.each_with_index do |option, index|
          unless option.respond_to?(:strike) && option.respond_to?(:open_interest)
            raise ArgumentError, "Option at index #{index} must respond to :strike and :open_interest"
          end
        end
      end

      def create_chart(symbol, contract_type, expiration_date)
        chart = Gruff::Bar.new(width)
        chart.title = "Open Interest for #{symbol} #{contract_type}s - Exp: #{expiration_date}"
        chart.title_font_size = 20
        chart.theme = contract_type_theme(contract_type)
        chart
      end

      def contract_type_theme(contract_type)
        base_theme = default_theme
        base_theme[:colors] = contract_type == 'CALL' ? ['#006400'] : ['#DC143C']
        base_theme
      end

      def configure_data(chart, open_interests, strikes)
        chart.data(:open_interest, open_interests)
        chart.labels = strikes.each_with_index.to_h do |strike, i|
          [i, strike.to_i.to_s]
        end
      end

      def configure_chart_options(chart, contract_type)
        configure_common_chart_options(chart)
        chart.y_axis_label = 'Open Interest'
        chart.x_axis_label = 'Strike Price'
      end

      def print_summary(options)
        puts "\nOpen Interest Summary:"
        puts "-" * 50
        puts "Strike | Open Interest"
        puts "-" * 50
        options.each do |opt|
          puts "#{opt.strike.to_s.ljust(6)} | #{opt.open_interest}"
        end
      end
    end
  end
end
