require_relative 'trade'

class NullTrade < Trade
  def credit_debit
    nil
  end

  def delta
    nil
  end
end
