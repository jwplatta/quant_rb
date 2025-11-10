require 'schwab_rb'
require 'securerandom'
require_relative 'trades_file_manager'

class IronCondorTrade
  class << self
    def open_trade
      TradesFileManager.instance.open_trade
    end
  end

  NEW_STATUS = 'NEW'.freeze
  OPEN_STATUS = 'OPEN'.freeze
  CLOSED_STATUS = 'CLOSED'.freeze
  STATUSES = [NEW_STATUS, OPEN_STATUS, CLOSED_STATUS].freeze

  def initialize(
    id: nil,
    put_spread:,
    call_spread:,
    expiration_date:,
    open_price:,
    open_fees: nil,
    open_commissions: nil,
    close_price: nil,
    close_fees: nil,
    close_commissions: nil,
    total_credit_debit: 0,
    total_fees: 0,
    total_commissions: 0,
    contracts: 1,
    exit_prof_thresh: EXIT_PROF_THRESH,
    exit_loss_thresh: EXIT_LOSS_THRESH,
    status: NEW_STATUS,
    price_increment: 0.05,
    trade_history: [],
    adjustment_count: 0
  )
    @id = id || SecureRandom.uuid().delete('-')
    @strategy_type = 'IRON_CONDOR'
    @call_spread = call_spread
    @put_spread = put_spread
    @expiration_date = expiration_date
    @open_price = open_price
    @open_fees = open_fees
    @open_commissions = open_commissions
    @close_price = close_price
    @close_fees = close_fees
    @close_commissions = close_commissions
    @total_credit_debit = total_credit_debit
    @total_fees = total_fees
    @total_commissions = total_commissions
    @exit_prof_thresh = exit_prof_thresh
    @exit_loss_thresh = exit_loss_thresh
    @contracts = contracts
    @status = status
    @price_increment = price_increment
    @trade_history = trade_history
    @adjustment_count = adjustment_count
  end

  attr_reader :id, :strategy_type, :call_spread, :put_spread, :expiration_date,
    :open_price, :close_price, :exit_prof_thresh, :exit_loss_thresh, :status,
    :contracts, :trade_history, :open_fees, :open_commissions, :close_fees, :close_commissions,
    :total_credit_debit, :total_fees, :total_commissions, :adjustment_count, :price_increment

  def symbols
    call_spread.symbols + put_spread.symbols
  end

  def profit_loss
    total_credit_debit - total_fees - total_commissions
  end

  def set_open(**order_details)
    fees = order_details.delete(:fees)
    commissions = order_details.delete(:commissions)
    price = order_details.delete(:price)
    quantity = order_details.delete(:quantity)
    credit_debit = calc_credit_debit(price, quantity, @cached_order_args[:credit_debit])

    update_history(price, fees, commissions, quantity)

    @status = OPEN_STATUS
    @open_price = price
    @open_fees = fees
    @open_commissions = commissions
    @total_credit_debit += credit_debit
    @total_fees += fees if fees
    @total_commissions += commissions if commissions

    trades_file_manager.create(self)
  end

  def set_adjustment(**order_details)
    # TODO: need to update the spreads if the contracts changed.
    fees = order_details.delete(:fees)
    commissions = order_details.delete(:commissions)
    price = order_details.delete(:price)
    quantity = order_details.delete(:quantity)
    credit_debit = calc_credit_debit(price, quantity, @cached_order_args[:credit_debit])

    update_history(price, fees, commissions, quantity)

    @adjustment_count += 1
    @total_credit_debit += credit_debit
    @total_fees += fees if fees
    @total_commissions += commissions if commissions

    trades_file_manager.update(self)
  end

  def set_close(**order_details)
    fees = order_details.delete(:fees)
    commissions = order_details.delete(:commissions)
    price = order_details.delete(:price)
    quantity = order_details.delete(:quantity)
    credit_debit = calc_credit_debit(price, quantity, @cached_order_args[:credit_debit])

    update_history(price, fees, commissions, quantity)

    @status = CLOSED_STATUS
    @close_price = price
    @close_fees = fees
    @close_commissions = commissions
    @total_credit_debit += credit_debit
    @total_fees += fees if fees
    @total_commissions += commissions if commissions

    trades_file_manager.update(self)
  end

  def calc_credit_debit(price, quantity, credit_debit_type)
    if credit_debit_type == :credit
      price * quantity * 100
    else
      price * quantity * -100
    end
  end

  def update_history(price, fees, commissions, quantity)
    trade_event = @cached_order_args.dup
    trade_event[:fees] = fees
    trade_event[:commissions] = commissions
    trade_event[:price] = price
    trade_event[:quantity] = quantity
    trade_event[:timestamp] = Time.now.utc.iso8601

    @trade_history << trade_event
    @cached_order_args = nil
  end

  def open?
    status == OPEN_STATUS
  end

  def closed?
    status == CLOSED_STATUS
  end

  def close_loss_price
    open_price * exit_loss_thresh
  end

  def max_loss_price
    round_down_to_nearest(open_price * exit_loss_thresh)
  end

  def break_even_price
    # this is per contract
    round_up_to_nearest((open_price * 100 + 2 * open_fees + 2 * open_commissions) / 100.0)
  end

  def target_profit_price
    # this is per contract
    round_down_to_nearest((open_price * 100 - open_fees - open_commissions) * exit_prof_thresh / 100.0)
  end

  def open_order_args
    @cached_order_args = {
      put_short_symbol: put_spread.short_leg.symbol,
      put_long_symbol: put_spread.long_leg.symbol,
      call_short_symbol: call_spread.short_leg.symbol,
      call_long_symbol: call_spread.long_leg.symbol,
      price: open_price,
      duration: SchwabRb::Orders::Duration::DAY,
      credit_debit: :credit,
      order_instruction: :open,
      quantity: contracts,
      strategy_type: SchwabRb::Order::ComplexOrderStrategyTypes::IRON_CONDOR
    }
  end

  def open_call_spread_args(price, calls_contracts = nil)
    @cached_order_args = {
      short_leg_symbol: call_spread.short_leg.symbol,
      long_leg_symbol: call_spread.long_leg.symbol,
      price: price,
      duration: SchwabRb::Orders::Duration::DAY,
      credit_debit: :credit,
      order_instruction: :open,
      quantity: calls_contracts || contracts,
      strategy_type: SchwabRb::Order::ComplexOrderStrategyTypes::VERTICAL
    }
  end

  def roll_call_spread_args(price, vertical_spread)
  end

  def open_put_spread_args(price, puts_contracts = nil)
    @cached_order_args = {
      short_leg_symbol: put_spread.short_leg.symbol,
      long_leg_symbol: put_spread.long_leg.symbol,
      price: price,
      duration: SchwabRb::Orders::Duration::DAY,
      credit_debit: :credit,
      order_instruction: :open,
      quantity: puts_contracts || contracts,
      strategy_type: SchwabRb::Order::ComplexOrderStrategyTypes::VERTICAL
    }
  end

  def roll_put_spread_args
  end

  def close_order_args(price)
    # TODO: either create custom error for this and rescue it in the bot and then handles the spreads separately.
    # Or you need to come up with the logic to ensure this doesn't happen in the bot.
    raise "Must close spreads separately! Unequal contracts." if call_spread.contracts != put_spread.contracts

    @cached_order_args = {
      put_short_symbol: put_spread.short_leg.symbol,
      put_long_symbol: put_spread.long_leg.symbol,
      call_short_symbol: call_spread.short_leg.symbol,
      call_long_symbol: call_spread.long_leg.symbol,
      price: price,
      duration: SchwabRb::Orders::Duration::DAY,
      credit_debit: :debit,
      order_instruction: :close,
      quantity: contracts,
      strategy_type: SchwabRb::Order::ComplexOrderStrategyTypes::IRON_CONDOR
    }
  end

  def close_call_spread_args(price)
    @cached_order_args = {
      short_leg_symbol: call_spread.short_leg.symbol,
      long_leg_symbol: call_spread.long_leg.symbol,
      price: price,
      duration: SchwabRb::Orders::Duration::DAY,
      credit_debit: :debit,
      order_instruction: :close,
      quantity: call_spread.contracts,
      strategy_type: SchwabRb::Order::ComplexOrderStrategyTypes::VERTICAL
    }
  end

  def close_put_spread_args(price)
    @cached_order_args = {
      short_leg_symbol: put_spread.short_leg.symbol,
      long_leg_symbol: put_spread.long_leg.symbol,
      price: price,
      duration: SchwabRb::Orders::Duration::DAY,
      credit_debit: :debit,
      order_instruction: :close,
      quantity: put_spread.contracts,
      strategy_type: SchwabRb::Order::ComplexOrderStrategyTypes::VERTICAL
    }
  end

  def round_up_to_nearest(value)
    ((value / @price_increment).ceil * @price_increment).round(2)
  end

  def round_down_to_nearest(value)
    ((value / @price_increment).floor * @price_increment).round(2)
  end

  def to_h
    {
      id: id,
      expiration_date: expiration_date,
      open_price: open_price,
      open_fees: open_fees,
      open_commissions: open_commissions,
      close_price: close_price,
      close_fees: close_fees,
      close_commissions: close_commissions,
      total_credit_debit: total_credit_debit,
      total_fees: total_fees,
      total_commissions: total_commissions,
      exit_prof_thresh: exit_prof_thresh,
      exit_loss_thresh: exit_loss_thresh,
      contracts: contracts,
      status: status,
      strategy_type: strategy_type,
      call_spread: call_spread.to_h,
      put_spread: put_spread.to_h,
      adjustment_count: adjustment_count,
      price_increment: price_increment,
      trade_history: trade_history.map(&:to_h)
    }
  end

  private

  def trades_file_manager
    TradesFileManager.instance
  end
end