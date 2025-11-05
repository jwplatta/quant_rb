# OptionChain = Struct.new

OptionLeg = Struct.new :symbol, :strike, :mark, :delta, :contract_type, :expiration_date do
  def to_h
    {
      symbol: symbol,
      strike: strike,
      mark: mark,
      delta: delta,
      contract_type: contract_type,
      expiration_date: expiration_date
    }
  end
end

VerticalSpread = Struct.new(:short_leg, :long_leg, :contract_type, :contracts) do
  def initialize(short_leg = nil, long_leg = nil, contract_type = nil, contracts = 1)
    super(short_leg, long_leg, contract_type, contracts)
  end

  def delta
    short_leg.delta.abs
  end

  def symbols
    [short_leg.symbol, long_leg.symbol]
  end

  def credit
    (short_leg.mark - long_leg.mark).round(2)
  end

  def debit
    (long_leg.mark - short_leg.mark).round(2)
  end

  def spread_width
    (long_leg.strike - short_leg.strike).abs
  end

  def to_h
    {
      short_leg: short_leg.to_h,
      long_leg: long_leg.to_h,
      contract_type: contract_type,
      contracts: contracts
    }
  end
end
