# frozen_string_literal: true

require_relative "options_trader/version"
require "tmpdir"
require "schwab_rb"

begin
  require 'dotenv'
  Dotenv.load

  require_relative '../config/environment'
rescue LoadError
  # dotenv not available, skip loading
  STDERR.puts "Warning: dotenv not available, skipping loading"
rescue Errno::ENOENT
  # .env file not found, continue without it
  STDERR.puts "Warning: .env file not found, continuing without it"
end

module OptionsTrader
  class Error < StandardError; end

  # Require configuration first
  require_relative "options_trader/configuration"
  require_relative 'options_trader/logger'
  require_relative 'options_trader/loggable'

  # Require constants
  require_relative "options_trader/constants"

  # Require data objects
  require_relative "options_trader/data_objects/option"
  require_relative "options_trader/data_objects/options_chain"

  # Require data providers
  require_relative "options_trader/data_providers/schwab/markets"
  require_relative "options_trader/data_providers/polygon/client"

  # Require predictors
  require_relative "options_trader/predictors/greek_forge"

  # Require services
  require_relative "options_trader/services/markets"
  require_relative "options_trader/services/historical_markets"
  require_relative "options_trader/services/schwab_exporter"
  require_relative "options_trader/services/polygon_importer"
  require_relative "options_trader/services/historical_snapshot"

  # Require schwab modules (needed by strategies)
  require_relative "options_trader/schwab/quoteable"
  require_relative "options_trader/schwab/schwab"

  # Then require strategy components
  require_relative "options_trader/strategies/strategy_base"
  require_relative "options_trader/strategies/call_option"
  require_relative "options_trader/strategies/put_option"
  require_relative "options_trader/strategies/call_spread"
  require_relative "options_trader/strategies/put_spread"
  require_relative "options_trader/strategies/iron_condor"
  require_relative "options_trader/strategies/null_strategy"

  # Finally require search components
  require_relative "options_trader/search/strategy_search_factory"
  require_relative "options_trader/search/iron_condor_search"
  require_relative "options_trader/search/vertical_spread_search"
  require_relative "options_trader/search/single_option_search"

  # Require trades components
  require_relative "options_trader/trades/trade"
  require_relative "options_trader/trades/trade_progress"
  require_relative "options_trader/trades/trade_journal"
  require_relative "options_trader/trades/order_manager"
  require_relative "options_trader/trades/risk_monitor"

  # Require bots
  require_relative "options_trader/automation/bot"

  # Require charts
  require_relative "options_trader/charts/chart_base"
  require_relative "options_trader/charts/monthly_progress"
  require_relative "options_trader/charts/line_graph"

  # Require exports
  require_relative "options_trader/exports/transactions_by_order"

  # Require job workers
  require_relative "options_trader/workers/sample_spx_option_chain_9dte"

  # Require models
  require_relative "options_trader/models/option_chain_history"
  require_relative "options_trader/models/price_history"

  # Require indicators
  require_relative "options_trader/indicators/greeks"
  require_relative "options_trader/indicators/implied_volatility"
  require_relative "options_trader/indicators/historical_volatility"
  require_relative "options_trader/indicators/vix_volatility"
  require_relative "options_trader/indicators/cox_ross_rubinstein"
  require_relative "options_trader/indicators/black_scholes"

  # Require MCP server
  require_relative "options_trader/mcp/server"

  # Require Utils
  require_relative "options_trader/utils/delta_interpolator"
  require_relative "options_trader/utils/option_price_interpolator"
  require_relative "options_trader/utils/monotonicity_enforcer"

  def self.create_bot(&block)
    builder = BotBuilder.new
    builder.instance_eval(&block)
    builder.build
  end

  class BotBuilder
    def initialize
      @config = {}
    end

    def set_name(name)
      @config[:name] = name
    end

    def set_mode(mode)
      @config[:mode] = mode
    end

    def set_interval(interval)
      @config[:sleep_interval] = interval
    end

    def set_account_name(account_name)
      @config[:account_name] = account_name
    end

    def enter_trade_when(timing)
      @config[:enter_timing] = timing
    end

    def use_strategy(strategy_type, &block)
      @config[:strategy_type] = strategy_type

      if block_given?
        strategy_builder = StrategyBuilder.new
        strategy_builder.instance_eval(&block)
        strategy_config = strategy_builder.build
        @config.merge!(strategy_config)
      end
    end

    def exit_when(&block)
      if block_given?
        exit_builder = ExitBuilder.new
        exit_builder.instance_eval(&block)
        exit_config = exit_builder.build
        @config.merge!(exit_config)
      end
    end

    def adjust_strategy_when(&block)
      # TODO: Implement strategy adjustment DSL
      puts "Strategy adjustment DSL not implemented yet"
    end

    def alert_when(&block)
      # TODO: Implement alert DSL
      puts "Alert DSL not implemented yet"
    end

    def build
      OptionsTrader::Automation::Bot.new(
        name: @config[:name],
        mode: @config[:mode] || :paper,
        account_name: @config[:account_name],
        config: @config
      )
    end
  end

  class StrategyBuilder
    def initialize
      @config = {}
    end

    def set_underlying_symbol(symbol)
      @config[:underlying_symbol] = symbol
    end

    def set_option_root(root)
      @config[:option_root] = root
    end

    def set_settlement_type(type)
      @config[:settlement_type] = type
    end

    def set_days_to_expiration(days)
      @config[:days_to_expiration] = days
    end

    def set_min_credit(amount)
      @config[:min_credit] = amount
    end

    def set_min_open_interest(amount)
      @config[:min_open_interest] = amount
    end

    def set_max_delta(delta)
      @config[:max_delta] = delta
    end

    def set_max_spread(spread)
      @config[:max_spread] = spread
    end

    def set_dist_from_strike(distance)
      @config[:dist_from_strike] = distance
    end

    def set_quantity(quantity)
      @config[:quantity] = quantity
    end

    def set_increment(increment)
      @config[:increment] = increment
    end

    def build
      @config
    end
  end

  class ExitBuilder
    def initialize
      @config = {}
    end

    def max_loss_threshold(multiplier)
      @config[:max_loss_threshold] = -multiplier.abs # Ensure negative for loss
    end

    def profit_target_threshold(percentage)
      @config[:profit_target_threshold] = percentage
    end

    def build
      @config
    end
  end
end
