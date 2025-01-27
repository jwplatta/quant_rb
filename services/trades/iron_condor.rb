require_relative 'trade'

class IronCondor < Trade
  attr_reader :strategy, :call_spread, :put_spread

  def initialize(call_spread:, put_spread:, approx_fees: 0.0488)
    @strategy = "IRON_CONDOR"
    @put_spread = put_spread
    @call_spread = call_spread
    @approx_fees = approx_fees
  end

  def prob_of_profit
    @pop ||= (1 - put_spread.delta.abs) + (1 - call_spread.delta.abs) - 1
  end

  def max_loss
    @max_loss ||= ([put_spread.spread_width, call_spread.spread_width].max - credit_debit) * 100.0
  end

  def credit_debit(include_fees: false)
    if include_fees
      put_spread.credit_debit + call_spread.credit_debit - @approx_fees
    else
      put_spread.credit_debit + call_spread.credit_debit
    end
  end

  def debit?
    credit_debit.negative?
  end

  def credit?
    credit_debit.positive?
  end

  def expected_return
    ((credit_debit * pop) - (max_loss * (1 - pop)))
  end

  def symbols
    put_spread.symbols + call_spread.symbols
  end
end
