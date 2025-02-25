require_relative 'trade'

class CallSpread < Trade
  attr_reader :strategy, :short_leg, :long_leg

  def initialize(
    positions: [],
    exit_threshold: 0.75,
    short_leg: nil,
    long_leg: nil,
    approx_fees: 0.0,
    increment: 0.01,
    round: 2
  )
    super(increment: increment, round: round)
    @strategy = "VERTICAL"
    @exit_threshold = exit_threshold
    @short_leg = short_leg ? short_leg : positions.find { |p| p.short?}
    @long_leg = long_leg ? long_leg : positions.find { |p| p.long? }
    @approx_fees = approx_fees
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
      strategy: strategy,
      symbols: symbols,
      short_leg: short_leg.to_h,
      long_leg: long_leg.to_h,
      entry_price: entry_price,
      exit_price: exit_price,
      progress: progress
    }
  end
end
