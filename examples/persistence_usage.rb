#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../config/environment'
require_relative '../services/repository'
require_relative '../services/trades/put_spread'

# Example of how to use the repository pattern with your business logic

# 1. Create a business logic object
put_spread = Services::Trades::PutSpread.new(
  underlying_symbol: 'SPY',
  short_strike: 430.0,
  long_strike: 420.0,
  expiration_date: Date.today + 30,
  quantity: 1
)

# 2. Execute business logic
put_spread.calculate_risk_reward

# 3. Persist the trade to the database
trade = Repository.save_trade(
  underlying: put_spread.underlying_symbol,
  strategy: 'PUT_SPREAD',
  open_date: Date.today
)

# 4. Create and save the trade legs
short_leg = Repository.save_trade_leg(
  trade_id: trade.id,
  put_call: 'PUT',
  symbol: 'SPY230630P00430000',
  mark: put_spread.short_option.mark,
  ask: put_spread.short_option.ask,
  bid: put_spread.short_option.bid,
  delta: put_spread.short_option.delta,
  strike: put_spread.short_strike,
  expiration_date: put_spread.expiration_date,
  instruction: 'SELL_TO_OPEN',
  quantity: put_spread.quantity
)

long_leg = Repository.save_trade_leg(
  trade_id: trade.id,
  put_call: 'PUT',
  symbol: 'SPY230630P00420000',
  mark: put_spread.long_option.mark,
  ask: put_spread.long_option.ask,
  bid: put_spread.long_option.bid,
  delta: put_spread.long_option.delta,
  strike: put_spread.long_strike,
  expiration_date: put_spread.expiration_date,
  instruction: 'BUY_TO_OPEN',
  quantity: put_spread.quantity
)

# 5. Save order information
order = Repository.save_order(
  trade_id: trade.id,
  order_id: '123456789',
  order_type: 'VERTICAL',
  underlying: put_spread.underlying_symbol,
  status: 'FILLED',
  strategy_type: 'PUT_SPREAD',
  adjustment: false,
  net_amount: put_spread.credit_debit * 100
)

# 6. Save transaction information
Repository.save_transaction(
  order_id: order.id,
  symbol: short_leg.symbol,
  description: 'SPY PUT 430 06/30/2023',
  put_call: 'PUT',
  trade_date: DateTime.now,
  instrument_id: 12_345,
  quantity: -1 * put_spread.quantity,
  fees: 0.65,
  commission: 0.00,
  cost: -1 * (put_spread.short_option.mark * 100),
  net_amount: -1 * (put_spread.short_option.mark * 100 + 0.65),
  position_effect: 'OPENING'
)

Repository.save_transaction(
  order_id: order.id,
  symbol: long_leg.symbol,
  description: 'SPY PUT 420 06/30/2023',
  put_call: 'PUT',
  trade_date: DateTime.now,
  instrument_id: 12_346,
  quantity: put_spread.quantity,
  fees: 0.65,
  commission: 0.00,
  cost: put_spread.long_option.mark * 100,
  net_amount: put_spread.long_option.mark * 100 + 0.65,
  position_effect: 'OPENING'
)

# 7. Retrieving the complete trade
complete_trade = Repository.find_complete_trade(trade.id)
puts "Retrieved trade: #{complete_trade[:trade].underlying} #{complete_trade[:trade].strategy}"
puts "Number of legs: #{complete_trade[:legs].size}"
puts "Number of orders: #{complete_trade[:orders].size}"
puts "Number of transactions: #{complete_trade[:transactions].size}"

# 8. Finding trades by underlying
spy_trades = Repository.find_trades_by_underlying('SPY')
puts "Found #{spy_trades.size} SPY trades"

# 9. Finding open trades
open_trades = Repository.find_open_trades
puts "Found #{open_trades.size} open trades"
