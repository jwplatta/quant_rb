require_relative 'lib/platypi'

#!/usr/bin/env ruby
# frozen_string_literal: true

bot = Platypi.create_bot do
  set_name 'SPX 1DTE Bot'
  set_mode :paper
  set_interval 1

  # set_account_name 'primary'

  # NOTE: optional setting
  enter_trade_when :immediately # :last_trading_hour | :opening

  use_strategy 'ironcondor' do
    set_underlying_symbol '$SPX'
    set_option_root 'SPXW'
    set_settlement_type 'P'
    set_days_to_expiration 1
    set_min_credit 0.5
    set_min_open_interest 0
    set_max_delta 0.07
    set_max_spread 15.0
    set_dist_from_strike 0.01
    set_quantity 1
    set_increment 0.05
  end

  exit_when do
    max_loss_threshold 0.00
    profit_target_threshold 0.00
  end

  # NOTE: optional, ignore for now
  # adjust_strategy_when do
  #   set_max_delta 0.22
  #   set_max_loss 2.0
  #   add_contracts true
  #
  #   do_rollup_when do
  #   end
  #   do_rollout_when do
  #     delta_above 0.40
  #   end
  # end

  # alert_when do
  # end
end

Signal.trap('INT') do
  puts "\nReceived interrupt signal..."
  bot.stop
  exit(0)
end

Signal.trap('TERM') do
  puts "\nReceived termination signal..."
  bot.stop
  exit(0)
end

puts "Starting bot..."
puts "Bot name: #{bot.name}"
puts "Bot mode: #{bot.mode}"
puts "Bot account: #{bot.account_name}" if bot.account_name
puts "Press Ctrl+C to stop"
puts ""

bot.clear_trade
bot.start
