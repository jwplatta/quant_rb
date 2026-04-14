require 'logger'

module OptionsTrader
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
        config = OptionsTrader.configuration

        if config.log_file && config.log_to_stdout
          MultiIOLogger.new(config.log_file, $stdout, config.log_level)
        elsif config.log_file
          logger = ::Logger.new(config.log_file)
          logger.level = log_level_constant(config.log_level)
          logger.formatter = log_formatter
          logger
        else
          logger = ::Logger.new($stdout)
          logger.level = log_level_constant(config.log_level)
          logger.formatter = log_formatter
          logger
        end
      end

      def log_level_constant(level)
        case level
        when :debug then ::Logger::DEBUG
        when :info then ::Logger::INFO
        when :warn then ::Logger::WARN
        when :error then ::Logger::ERROR
        when :fatal then ::Logger::FATAL
        else ::Logger::INFO
        end
      end

      def log_formatter
        proc do |severity, datetime, progname, msg|
          "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
        end
      end
    end
  end

  class MultiIOLogger
    def initialize(file_path, stdout, log_level)
      @file_logger = ::Logger.new(file_path)
      @stdout_logger = ::Logger.new(stdout)

      level_constant = case log_level
      when :debug then ::Logger::DEBUG
      when :info then ::Logger::INFO
      when :warn then ::Logger::WARN
      when :error then ::Logger::ERROR
      when :fatal then ::Logger::FATAL
      else ::Logger::INFO
      end

      formatter = proc do |severity, datetime, progname, msg|
        "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
      end

      @file_logger.level = level_constant
      @stdout_logger.level = level_constant
      @file_logger.formatter = formatter
      @stdout_logger.formatter = formatter
    end

    [:debug, :info, :warn, :error, :fatal].each do |level|
      define_method(level) do |message|
        @file_logger.send(level, message)
        @stdout_logger.send(level, message)
      end
    end

    def level=(new_level)
      @file_logger.level = new_level
      @stdout_logger.level = new_level
    end
  end
end
