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
  require_relative "platypi/search/strategy_finder_factory"
  require_relative "platypi/search/call_spread_finder"
  require_relative "platypi/search/put_spread_finder"
  require_relative "platypi/search/iron_condor_finder"

  # Require trades components
  require_relative "platypi/trades"
  require_relative "platypi/trades/trade"
  require_relative "platypi/trades/trade_progress"
  require_relative "platypi/trades/trade_journal"
  require_relative "platypi/trades/order_manager"
  require_relative "platypi/trades/risk_monitor"

  # Require bots
  require_relative "platypi/automation/bot"

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

    def set_account(account)
      @config[:account] = account
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
      Platypi::Automation::Bot.new(
        name: @config[:name],
        mode: @config[:mode] || :paper,
        account: @config[:account],
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
