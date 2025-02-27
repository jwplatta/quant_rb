require 'schwab_rb'

class Trade
  attr_accessor :increment, :round

  def initialize(increment: 0.01, round: 2)
    @increment = increment
    @round = round
  end

  def debit_credit
    raise "Must be implemented in subclass"
  end

  def delta
    raise "Must be implemented in subclass"
  end

  def nearest_increment(value)
    (value / increment).floor * increment
  end
end
