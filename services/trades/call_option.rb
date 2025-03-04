require_relative "trade"

class CallOption < Trade
  class << self
    def from_h(hash)
      expiration_date = hash[:expiration_date] ? Date.parse(hash[:expiration_date]) : nil
      CallOption.new(
        hash[:symbol],
        strike: hash[:strike],
        expiration_date: expiration_date,
        quantity: hash.fetch(:quantity, nil),
        open_credit_debit: hash.fetch(:open_credit_debit, nil),
        open_date: hash.fetch(:open_date, nil),
        open_fees: hash.fetch(:open_fees, nil),
        open_commission: hash.fetch(:open_commission, nil),
      )
    end

    def from_quote(quote)
      expiration_date = Date.new(
        quote.expiration_year,
        quote.expiration_month,
        quote.expiration_day
      )
      CallOption.new(
        quote.symbol,
        strike: quote.strike_price,
        delta: quote.delta,
        mark: quote.mark,
        ask: quote.ask_price,
        bid: quote.bid_price,
        expiration_date: expiration_date
      )
    end
  end

  attr_reader :symbol, :strike, :delta, :mark, :ask, :bid, :expiration_date

  def initialize(
    symbol, strike: nil, delta: 999, mark: nil, ask: nil, bid: nil,
    expiration_date: nil, quantity: nil, increment: 0.01, round: 2
  )
    super(
      increment: increment,
      round: round,
      quantity: quantity
    )
    @strategy = "SINGLE"
    @symbol = symbol
    @strike = strike
    @delta = delta.abs
    @mark = mark
    @ask = ask
    @bid = bid
    @expiration_date = expiration_date
  end

  def risk_status
    if delta.abs < 0.16
      "GREEN"
    elsif delta.abs < 0.3
      "YELLOW"
    else
      "RED"
    end
  end

  def tested?
    risk_status == "YELLOW"
  end

  def danger?
    risk_status == "RED"
  end

  def credit_debit
    nearest_increment(mark.round(2))
  end

  def net_credit_debit
    credit_debit * 100 - open_fees - open_commission
  end

  def short?
    quantity < 0
  end

  def long?
    quantity > 0
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

  ##################
  ### Schwab API ###
  ##################

  def check_market
    quote(symbol).then do |quote|
      @delta = quote.delta.abs
      @mark = quote.mark
      @ask = quote.ask_price
      @bid = quote.bid_price
      @strike = quote.strike_price
      @expiration_date = Date.new(
        quote.expiration_year,
        quote.expiration_month,
        quote.expiration_day
      )
    end
  end

  def to_h
    {
      type: "CALL",
      symbol: symbol,
      strike: strike,
      quantity: quantity,
      expiration_date: expiration_date,
      open_credit_debit: open_credit_debit,
      open_date: open_date,
      open_fees: open_fees,
      open_commission: open_commission,
    }
  end
end
