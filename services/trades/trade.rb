require_relative "../../mixins/schwab/schwab"
require_relative "../../mixins/orderable"

Order = Struct.new(:id, :status, :date)

class Trade
  include Schwab
  include Orderable
  # include Logger
  # include Adjustable

  attr_accessor :increment, :round, :open_credit_debit, :open_date,
    :open_fees, :open_commission, :exit_threshold, :max_loss, :quantity,
    :order_id, :order_status, :order_rejects, :transactions, :underlying_symbol

  module Actions
    EXIT_LOSS="EXIT_LOSS"
    EXIT_PROFIT="EXIT_PROFIT"
    HOLD="HOLD"
    ADJUST="ADJUST"
    ADJUST_PUT="ADJUST_PUT"
    ADJUST_CALL="ADJUST_CALL"
    ROLL_UP="ROLL_UP"
    ROLL_DOWN="ROLL_AWAY"
    ROLL_OUT="ROLL_OUT"
  end

  def initialize(
    underlying_symbol: nil, increment: 0.01,
    round: 2, open_credit_debit: nil, open_date: nil,
    open_fees: 0.0, open_commission: 0.0,
    exit_threshold: 0.75, max_loss: -3.0, quantity: 1
  )
    @underlying_symbol = underlying_symbol
    @increment = increment
    @round = round
    @open_credit_debit = open_credit_debit
    @open_date = open_date
    @open_fees = open_fees
    @open_commission = open_commission
    @exit_threshold = exit_threshold
    @max_loss = max_loss
    @quantity = quantity
    @order_id = nil
    @order_status = nil
    @order_rejects = []
    @transactions = []
  end

  def credit_debit
    raise "Must be implemented in subclass"
  end

  def net_credit_debit
    raise "Must be implemented in subclass"
  end

  def delta
    raise "Must be implemented in subclass"
  end

  def check_market
    raise "Must be implemented in subclass"
  end

  def order_id=(id)
    @order_id = id
  end

  def add_transaction(transaction)
    @transactions << transaction
  end

  def exitable?
    progress >= exit_threshold || progress <= max_loss
  end

  def progress
    return nil unless open_credit_debit

    (net_credit_debit - net_open_credit_debit) / net_open_credit_debit
  end

  def net_open_credit_debit
    open_credit_debit * 100 - open_fees - open_commission
  end

  def order_id=(id)
    @order_id = id
  end

  def open_credit_debit=(credit_debit)
    @open_credit_debit = credit_debit
  end

  def open_date=(date)
    @open_date = date
  end

  def open_fees=(fees)
    @open_fees = fees
  end

  def open_commission=(commission)
    @open_commission = commission
  end

  def nearest_increment(value)
    (value / increment).floor * increment
  end

  def to_json
    to_h.to_json
  end
end
