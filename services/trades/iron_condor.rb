require_relative 'trade'

class IronCondor < Trade
  class << self
    def from_h(hash)
      call_spread = CallSpread.from_h(hash[:call_spread])
      put_spread = PutSpread.from_h(hash[:put_spread])
      expiration_date = hash[:expiration_date] ? Date.parse(hash[:expiration_date]) : nil
      IronCondor.new(
        call_spread: call_spread,
        put_spread: put_spread,
        expiration_date: expiration_date
      )
    end
  end

  attr_reader :strategy, :call_spread, :put_spread, :expiration_date

  def initialize(call_spread:, put_spread:, expiration_date:, increment: 0.01, round: 2, quantity: 1)
    super(increment: increment, round: round, quantity: quantity)
    @strategy = "IRON_CONDOR"
    @put_spread = put_spread
    @call_spread = call_spread
    @expiration_date = expiration_date
  end

  def complex?
    true
  end

  def prob_of_profit
    @pop ||= (1 - put_spread.delta.abs) + (1 - call_spread.delta.abs) - 1
  end

  def max_loss
    @max_loss ||= ([put_spread.spread_width, call_spread.spread_width].max - credit_debit) * 100.0
  end

  def credit_debit
    nearest_increment(
      put_spread.credit_debit_raw + call_spread.credit_debit_raw
    ).round(2)
  end

  def credit_debit_raw
    put_spread.credit_debit_raw + call_spread.credit_debit_raw
  end

  def credit_debit_with_fees
    put_spread.credit_debit + call_spread.credit_debit - (fees + commission)
  end

  def debit?
    credit_debit.negative?
  end

  def credit?
    credit_debit.positive?
  end

  def expected_return
    ((credit_debit * prob_of_profit) - (max_loss * (1 - prob_of_profit)))
  end

  def symbols
    put_spread.symbols + call_spread.symbols
  end

  def check_market
    call_spread.check_market
    put_spread.check_market
  end

  def to_h
    {
      type: "IRON_CONDOR",
      strategy: strategy,
      expiration_date: expiration_date,
      call_spread: call_spread.to_h,
      put_spread: put_spread.to_h,
    }.merge(orderable_h)
  end
end
