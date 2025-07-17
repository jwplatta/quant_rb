# frozen_string_literal: true

require_relative 'charts/base'
require_relative 'charts/monthly_progress'
require_relative 'charts/open_interest'

module OptionsTrader
  module Charts
    # Charts module for generating various types of financial charts
    #
    # Available chart types:
    # - MonthlyProgress: For displaying monthly trading progress
    # - OpenInterest: For displaying option open interest data
    #
    # Usage:
    #   chart = OptionsTrader::Charts::MonthlyProgress.new
    #   filepath = chart.generate(data, year: 2025, account_name: 'trading')
  end
end
