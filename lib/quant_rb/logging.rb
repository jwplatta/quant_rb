# frozen_string_literal: true

require "logger"

module QuantRb
  module Logging
    class << self
      def logger
        @logger ||= build_logger(level: QuantRb.config.log_level)
      end

      def logger=(new_logger)
        @logger = new_logger
      end

      def reset_logger!
        @logger = nil
      end

      def build_logger(output: $stdout, level: :info)
        logger = ::Logger.new(output)
        logger.level = level_constant(level)
        logger.formatter = formatter
        logger
      end

      def apply_config!
        logger.level = level_constant(QuantRb.config.log_level)
        logger
      end

      def level_constant(level)
        case level.to_s.downcase.to_sym
        when :debug then ::Logger::DEBUG
        when :info then ::Logger::INFO
        when :warn then ::Logger::WARN
        when :error then ::Logger::ERROR
        when :fatal then ::Logger::FATAL
        else ::Logger::INFO
        end
      end

      private

      def formatter
        proc do |severity, datetime, _progname, msg|
          "[#{datetime.utc.strftime('%Y-%m-%d %H:%M:%S UTC')}] #{severity}: #{msg}\n"
        end
      end
    end
  end
end
