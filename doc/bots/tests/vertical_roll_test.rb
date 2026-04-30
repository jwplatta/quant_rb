#!/usr/bin/env ruby
# frozen_string_literal: true

require 'pry'
require 'date'
require 'schwab_rb'
require 'json'
require 'fileutils'
require 'logger'

require_relative '../../lib/options_trader'
require_relative '../spx_1dte/data_objects'
require_relative '../spx_1dte/adjustment_finder'
require_relative '../spx_1dte/util'

ACCOUNT_NAME = 'TRADING_BROKERAGE_ACCOUNT'

SchwabRb.configure do |config|
  config.log_file = 'bots/tests/tmp/spx_1dte_bot.log'
  config.log_level = "INFO"
  config.silence_output = false
end

old_short_leg_symbol = "SPXW  251112P06765000"
old_long_leg_symbol = "SPXW  251112P06745000"

# NOTE: roll up
# new_short_leg_symbol = "SPXW  251112P06800000"
# new_long_leg_symbol = "SPXW  251112P06780000"

# NOTE: roll away
new_short_leg_symbol = "SPXW  251112P06735000"
new_long_leg_symbol = "SPXW  251112P06715000"

schwab_orders = OptionsTrader::DataProviders::Schwab::Orders.new(account_name: ACCOUNT_NAME)

order_args = {
  close_short_leg_symbol: old_short_leg_symbol,
  close_long_leg_symbol: old_long_leg_symbol,
  open_short_leg_symbol: new_short_leg_symbol,
  open_long_leg_symbol: new_long_leg_symbol,
  price: 0.1,
  strategy_type: SchwabRb::Order::ComplexOrderStrategyTypes::VERTICAL_ROLL,
  credit_debit: :debit,
  quantity: 3
}

result = schwab_orders.preview_order(order_instruction: :open, **order_args)

binding.pry