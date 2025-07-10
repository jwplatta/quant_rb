module Platypi
  class Configuration
    attr_accessor :log_level, :log_file, :log_to_stdout

    def initialize
      @log_level = :info
      @log_file = nil
      @log_to_stdout = true
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
      Platypi::Logger.logger
    end
  end
end
