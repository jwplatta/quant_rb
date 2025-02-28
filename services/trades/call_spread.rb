require_relative 'trade'
require_relative 'call_option'

class CallSpread < Trade
  class << self
    def from_h(hash)
      short_leg = CallOption.from_h(hash[:short_leg])
      long_leg = CallOption.from_h(hash[:long_leg])
      expiration_date = hash[:expiration_date] ? Date.parse(hash[:expiration_date]) : nil
      CallSpread.new(
        short_leg: short_leg,
        long_leg: long_leg,
        expiration_date: expiration_date,
      )
    end
  end

  attr_reader :strategy, :short_leg, :long_leg, :expiration_date

  def initialize(
    short_leg: nil,
    long_leg: nil,
    expiration_date: nil,
    increment: 0.01,
    round: 2
  )
    super(increment: increment, round: round)
    @strategy = "VERTICAL"
    @short_leg = short_leg
    @long_leg = long_leg
    @expiration_date
  end

  def complex?
    true
  end

  def delta
    short_leg.delta
  end

  def credit_debit
    nearest_increment(short_leg.mark - long_leg.mark).round(2)
  end

  def credit_debit_raw
    short_leg.mark - long_leg.mark
  end

  def spread_width
    @spread_width ||= (long_leg.strike - short_leg.strike).abs
  end

  def symbols
    [short_leg.symbol, long_leg.symbol]
  end

  def exitable?
    progress >= @exit_threshold
  end

  def progress
    1 - (exit_price * -1 / entry_price)
  end

  def entry_price
    @entry_price ||= (long_leg.average_price * 100 * -1) + (short_leg.average_price * 100)
  end

  def exit_price
    @exit_price ||= long_leg.market_value + short_leg.market_value
  end

  def to_h
    {
      type: "CALL_SPREAD",
      strategy: strategy,
      symbols: symbols,
      expiration_date: expiration_date,
      open_credit_debit: open_credit_debit,
      open_date: open_date,
      open_fees: open_fees,
      open_commission: open_commission,
      short_leg: short_leg.to_h,
      long_leg: long_leg.to_h,
    }
  end
end
