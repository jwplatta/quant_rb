# frozen_string_literal: true

module QuantRb
  CALL = "CALL".freeze
  PUT  = "PUT".freeze

  module Intervals
    MINUTE        = "1min".freeze
    FIVE_MIN      = "5min".freeze
    TEN_MIN       = "10min".freeze
    FIFTEEN_MIN   = "15min".freeze
    THIRTY_MIN    = "30min".freeze
    HOURLY        = "hourly".freeze
    DAILY         = "daily".freeze
    WEEKLY        = "weekly".freeze
    MONTHLY       = "monthly".freeze

    ALL = [MINUTE, FIVE_MIN, TEN_MIN, FIFTEEN_MIN, THIRTY_MIN, HOURLY, DAILY, WEEKLY, MONTHLY].freeze

    RESOLUTION_MAP = {
      minute:   MINUTE,
      "5min":   FIVE_MIN,
      "10min":  TEN_MIN,
      "15min":  FIFTEEN_MIN,
      "30min":  THIRTY_MIN,
      hourly:   HOURLY,
      daily:    DAILY,
      weekly:   WEEKLY,
      monthly:  MONTHLY
    }.freeze
  end
end
