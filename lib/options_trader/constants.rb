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
end
