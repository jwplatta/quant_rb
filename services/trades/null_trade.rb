require_relative 'trade'

class NullTrade < Trade
  def debit_credit
    nil
  end

  def delta
    nil
  end
end
