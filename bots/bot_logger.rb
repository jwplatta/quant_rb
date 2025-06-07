require 'logger'
require 'singleton'

class BotLogger
  include Singleton

  def initialize
    @logger = Logger.new($stdout).tap do |log|
      log.progname = 'BotLogger'
      log.level = Logger::INFO
      log.formatter = proc do |severity, datetime, progname, msg|
        "[#{datetime}] #{severity} (#{progname}): #{msg}\n"
      end
    end
  end

  def info(message)
    @logger.info(message)
  end

  def error(message)
    @logger.error(message)
  end

  def debug(message)
    @logger.debug(message)
  end

  def warn(message)
    @logger.warn(message)
  end
end

