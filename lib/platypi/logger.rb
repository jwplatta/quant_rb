require 'logger'

module Platypi
  module Logger
    class << self
      def logger
        @logger ||= create_logger
      end

      def logger=(new_logger)
        @logger = new_logger
      end

      def level=(level)
        logger.level = level
      end

      private

      def create_logger
        logger = ::Logger.new(log_destination)
        logger.level = log_level
        logger.formatter = log_formatter
        logger
      end

      def log_destination
        if ENV['LOG_FILE']
          File.open(ENV['LOG_FILE'], 'a')
        else
          $stdout
        end
      end

      def log_level
        case ENV['LOG_LEVEL']&.upcase
        when 'DEBUG' then ::Logger::DEBUG
        when 'INFO' then ::Logger::INFO
        when 'WARN' then ::Logger::WARN
        when 'ERROR' then ::Logger::ERROR
        when 'FATAL' then ::Logger::FATAL
        else ::Logger::INFO
        end
      end

      def log_formatter
        proc do |severity, datetime, progname, msg|
          "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}]"
        end
      end
    end

    def log_debug(msg)
      Platypi::Logger.logger.debug(msg)
    end

    def log_info(msg)
      Platypi::Logger.logger.info(msg)
    end

    def log_warn(msg)
      Platypi::Logger.logger.warn(msg)
    end

    def log_error(msg)
      Platypi::Logger.logger.error(msg)
    end

    def log_fatal(msg)
      Platypi::Logger.logger.fatal(msg)
    end
  end
end
