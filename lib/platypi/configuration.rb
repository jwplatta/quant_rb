module Platypi
  class Configuration
    attr_accessor :log_level, :log_file, :log_to_stdout

    def initialize
      @log_level = :info
      @log_file = nil
      @log_to_stdout = true
    end

    def logger
      @logger ||= create_logger
    end

    private

    def create_logger
      outputs = []
      outputs << $stdout if @log_to_stdout
      outputs << @log_file if @log_file

      if outputs.length == 1
        ::Logger.new(outputs.first)
      else
        MultiLogger.new(outputs)
      end
    end
  end

  class << self
    def configure
      yield configuration
    end

    def configuration
      @configuration ||= Configuration.new
    end

    def logger
      configuration.logger
    end
  end
end
