# frozen_string_literal: true

require_relative "platypi/version"

# Load environment variables globally for the gem
begin
  require 'dotenv'
  Dotenv.load
rescue LoadError
  # dotenv not available, skip loading
rescue Errno::ENOENT
  # .env file not found, continue without it
end

module Platypi
  class Error < StandardError; end

  # Require schwab data objects first
  require_relative "platypi/schwab/data_objects/account"
  require_relative "platypi/schwab/data_objects/instrument"
  require_relative "platypi/schwab/data_objects/option"
  require_relative "platypi/schwab/data_objects/option_chain"
  require_relative "platypi/schwab/data_objects/order"
  require_relative "platypi/schwab/data_objects/order_leg"
  require_relative "platypi/schwab/data_objects/order_preview"
  require_relative "platypi/schwab/data_objects/position"
  require_relative "platypi/schwab/data_objects/quote"
  require_relative "platypi/schwab/data_objects/transaction"

  # Require schwab modules (needed by strategies)
  require_relative "platypi/schwab/orderable"
  require_relative "platypi/schwab/quoteable"
  require_relative "platypi/schwab/schwab"

  # Then require strategy components
  require_relative "platypi/strategies/strategy_base"
  require_relative "platypi/strategies/call_option"
  require_relative "platypi/strategies/put_option"
  require_relative "platypi/strategies/call_spread"
  require_relative "platypi/strategies/put_spread"
  require_relative "platypi/strategies/iron_condor"
  require_relative "platypi/strategies/null_strategy"

  # Finally require search components
  require_relative "platypi/search/call_spread_finder"
  require_relative "platypi/search/put_spread_finder"
  require_relative "platypi/search/iron_condor_finder"

  # Require trades components
  require_relative "platypi/trades"
  require_relative "platypi/trades/trade_progress"
  require_relative "platypi/trades/trade_journal"
  require_relative "platypi/trades/trade"
end