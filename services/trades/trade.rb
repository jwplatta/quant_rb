require 'schwab_rb'

class Trade
  attr_accessor :increment, :round, :open_credit_debit, :open_date, :open_fees, :open_commission

  def initialize(increment: 0.01, round: 2, open_credit_debit: nil, open_date: nil, open_fees: 0.0, open_commission: 0.0)
    @increment = increment
    @round = round
    @open_credit_debit = open_credit_debit
    @open_date = open_date
    @open_fees = open_fees
    @open_commission = open_commission
  end

  def complex?
    false
  end

  def credit_debit
    raise "Must be implemented in subclass"
  end

  def delta
    raise "Must be implemented in subclass"
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
