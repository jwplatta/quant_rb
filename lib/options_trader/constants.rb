module OptionsTrader
  CALL = 'call'.freeze
  PUT = 'put'.freeze
  IRONCONDOR = 'ironcondor'.freeze
  VERTICAL = 'vertical'.freeze
  SINGLE = 'single'.freeze
  VALID_STRATEGIES = [
    IRONCONDOR,
    VERTICAL,
    SINGLE
  ].freeze
  module Intervals
    ONE_MIN = '1min'.freeze
    FIVE_MIN = '5min'.freeze
    TEN_MIN = '10min'.freeze
    DAILY = 'daily'.freeze
  end
end
