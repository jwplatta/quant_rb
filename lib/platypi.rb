# frozen_string_literal: true

require_relative "platypi/version"

module Platypi
  class Error < StandardError; end

  # Require schwab modules first (needed by strategies)
  require_relative "platypi/schwab/orderable"
  require_relative "platypi/schwab/quoteable"
  require_relative "platypi/schwab/schwab"

  # Then require strategy components
  require_relative "platypi/strategies/strategy_base"
  require_relative "platypi/strategies/strategy_factory"
  require_relative "platypi/strategies/call_option"
  require_relative "platypi/strategies/put_option"
  require_relative "platypi/strategies/call_spread"
  require_relative "platypi/strategies/put_spread"
  require_relative "platypi/strategies/iron_condor"
  require_relative "platypi/strategies/null_trade"

  # Finally require search components
  require_relative "platypi/search/call_spread_finder"
  require_relative "platypi/search/put_spread_finder"
  require_relative "platypi/search/iron_condor_finder"
end