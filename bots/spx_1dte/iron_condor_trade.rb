require 'securerandom'
require_relative 'trades_file_manager'
require_relative 'data_objects'

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

  # TODO: move these to the trade manager
  OPEN_ACTION = 'OPEN'.freeze
  ADJUST_ACTION = 'ADJUST'.freeze
  CLOSE_ACTION = 'CLOSE'.freeze
  ACTIONS = [OPEN_ACTION, ADJUST_ACTION, CLOSE_ACTION].freeze

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
    adjustment_count: 0,
    markets: nil
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
    @markets = markets
  end

  attr_reader :id, :strategy_type, :call_spread, :put_spread, :expiration_date,
    :open_price, :close_price, :exit_prof_thresh, :exit_loss_thresh, :status,
    :contracts, :trade_history, :open_fees, :open_commissions, :close_fees, :close_commissions,
    :total_credit_debit, :total_fees, :total_commissions, :adjustment_count, :price_increment, :markets

  def symbols
    call_spread.symbols + put_spread.symbols
  end

  def profit_loss
    total_credit_debit - total_fees - total_commissions
  end

  def check_market
    call_short_leg = markets.get_quote(call_spread.short_leg.symbol).then do |q|
      build_leg(q.symbol, q.strike, q.mark, q.delta, q.contract_type, q.expiration_date)
    end
    call_long_leg = markets.get_quote(call_spread.long_leg.symbol).then do |q|
      build_leg(q.symbol, q.strike, q.mark, q.delta, q.contract_type, q.expiration_date)
    end
    @call_spread = VerticalSpread.new(call_short_leg, call_long_leg, 'CALL')

    put_short_leg = markets.get_quote(put_spread.short_leg.symbol).then do |q|
      build_leg(q.symbol, q.strike, q.mark, q.delta, q.contract_type, q.expiration_date)
    end
    put_long_leg = markets.get_quote(put_spread.long_leg.symbol).then do |q|
      build_leg(q.symbol, q.strike, q.mark, q.delta, q.contract_type, q.expiration_date)
    end
    @put_spread = VerticalSpread.new(put_short_leg, put_long_leg, 'PUT')
  end

  def build_leg(symbol, strike, mark, delta, contract_type, expiration_date)
    OptionLeg.new(
      symbol,
      strike,
      mark,
      delta,
      contract_type,
      expiration_date
    )
  end

  # NOTE: this is WorkingOrder object
  def open(order)
    fees = order.details[:fees]
    commissions = order.details[:commissions]
    price = order.details[:price]
    quantity = order.details[:quantity]
    credit_debit = calc_credit_debit(price, quantity, :credit)

    update_history(OPEN_ACTION, order)

    @status = OPEN_STATUS
    @open_price = price
    @open_fees = fees
    @open_commissions = commissions
    @total_credit_debit += credit_debit
    @total_fees += fees if fees
    @total_commissions += commissions if commissions

    trades_file_manager.create(self)
  end

  def adjust(order)
    # TODO: need to update the spreads if the contracts changed.
    fees = order.details[:fees]
    commissions = order.details[:commissions]
    price = order.details[:price]
    quantity = order.details[:quantity]
    credit_debit = calc_credit_debit(price, quantity, :credit)

    update_history(order)

    @adjustment_count += 1
    @total_credit_debit += credit_debit
    @total_fees += fees if fees
    @total_commissions += commissions if commissions

    trades_file_manager.update(self)
  end

  def close(order)
    fees = order.details[:fees]
    commissions = order.details[:commissions]
    price = order.details[:price]
    quantity = order.details[:quantity]
    credit_debit = calc_credit_debit(price, quantity, :debit)

    update_history(CLOSE_ACTION, order)

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

  def update_history(action, order)
    trade_event = order.details.dup
    trade_event[:timestamp] = Time.now.utc.iso8601

    @trade_history << trade_event
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