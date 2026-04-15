# frozen_string_literal: true

require "csv"
require "fileutils"
require "json"
require "securerandom"

module QuantRb
  module Reporting
    class BacktestOutputWriter
      DEFAULT_DIR = File.expand_path("~/.quant_rb/backtests")
      SUPPORTED_FORMATS = %i[csv json].freeze

      def initialize(result, output_dir: DEFAULT_DIR, format: :csv, name: nil)
        @result = result
        @output_dir = File.expand_path(output_dir)
        @format = normalize_format(format)
        @name = normalize_name(name)
      end

      def save
        FileUtils.mkdir_p(@output_dir)

        summary_path = File.join(@output_dir, "#{@name}_summary.#{@format}")
        trades_path = File.join(@output_dir, "#{@name}_trades.#{@format}")

        write_summary(summary_path)
        write_trades(trades_path)

        { summary_path: summary_path, trades_path: trades_path, format: @format, name: @name }
      end

      private

      def normalize_format(format)
        normalized = format.to_s.downcase.to_sym
        return normalized if SUPPORTED_FORMATS.include?(normalized)

        raise ArgumentError, "Unsupported backtest output format: #{format}"
      end

      def normalize_name(name)
        return sanitize_name(name) if name && !name.to_s.strip.empty?

        SecureRandom.hex(6)
      end

      def sanitize_name(name)
        sanitized = name.to_s.strip.gsub(/[^a-zA-Z0-9_-]+/, "_").gsub(/\A_+|_+\z/, "")
        return sanitized unless sanitized.empty?

        SecureRandom.hex(6)
      end

      def write_summary(path)
        @format == :csv ? write_summary_csv(path) : write_summary_json(path)
      end

      def write_trades(path)
        @format == :csv ? write_trades_csv(path) : write_trades_json(path)
      end

      def summary_rows
        summary = @result.to_h.dup
        metrics = summary.delete(:metrics)
        summary.delete(:trades)

        rows = summary.map { |key, value| [key, value] }
        rows.concat(metrics.map { |key, value| [key, value] })
        rows
      end

      def write_summary_csv(path)
        CSV.open(path, "w") do |csv|
          csv << %w[field value]
          summary_rows.each { |row| csv << row }
        end
      end

      def write_trades_csv(path)
        trade_hashes = @result.trades.map(&:to_h)
        headers = trade_hashes.empty? ? default_trade_headers : trade_hashes.flat_map(&:keys).uniq

        CSV.open(path, "w") do |csv|
          csv << headers
          trade_hashes.each do |trade|
            csv << headers.map { |header| serialize_csv_value(trade[header]) }
          end
        end
      end

      def write_summary_json(path)
        payload = normalize_json_value(@result.to_h.reject { |key, _| key == :trades })
        File.write(path, JSON.pretty_generate(payload))
      end

      def write_trades_json(path)
        File.write(path, JSON.pretty_generate(normalize_json_value(@result.trades.map(&:to_h))))
      end

      def default_trade_headers
        %i[id strategy_class symbol direction quantity entry_price exit_price entry_time exit_time pnl winner duration_min legs notes]
      end

      def serialize_csv_value(value)
        case value
        when Array, Hash
          JSON.generate(value)
        else
          value
        end
      end

      def normalize_json_value(value)
        case value
        when Hash
          value.transform_values { |nested| normalize_json_value(nested) }
        when Array
          value.map { |nested| normalize_json_value(nested) }
        when Float
          return value if value.finite?

          value.positive? ? "Infinity" : "-Infinity"
        else
          value
        end
      end
    end
  end
end
