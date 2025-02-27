require_relative 'trade'

class CallOption < Trade
  attr_reader :symbol, :strike, :delta, :mark, :ask, :bid, :expiration_date, :quantity

  def initialize(symbol, strike, delta, mark, ask, bid, expiration_date, quantity)
    @symbol = symbol
    @strike = strike
    @delta = delta
    @mark = mark
    @ask = ask
    @bid = bid
    @expiration_date = expiration_date
    @quantity = quantity
  end

  def debit_credit
    mark.round(2)
  end

  def quantity=(new_quantity)
    @quantity = new_quantity
  end

  def instruction
    if quantity < 0
      "SELL_TO_OPEN"
    elsif quantity > 0
      "BUY_TO_CLOSE"
    end
  end
end