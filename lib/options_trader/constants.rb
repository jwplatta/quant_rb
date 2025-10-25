module OptionsTrader
  CALL = 'CALL'.freeze
  PUT = 'PUT'.freeze
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
    FIFTEEN_MIN = '15min'.freeze
    THIRTY_MIN = '30min'.freeze
    DAILY = 'daily'.freeze
    HOURLY = 'hourly'.freeze
    WEEKLY = 'weekly'.freeze
    MONTHLY = 'monthly'.freeze
    YEARLY = 'yearly'.freeze

    ALL_INTERVALS = [
      ONE_MIN,
      FIVE_MIN,
      TEN_MIN,
      FIFTEEN_MIN,
      THIRTY_MIN,
      HOURLY,
      DAILY,
      WEEKLY,
      MONTHLY,
      YEARLY
    ]
  end


  COX_ROSS_RUBINSTEIN = 'CoxRossRubinstein'.freeze
  BLACK_SCHOLES = 'BlackScholes'.freeze
  BINOMIAL = 'Binomial'.freeze
end
