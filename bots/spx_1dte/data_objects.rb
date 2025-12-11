require_relative 'util'
require_relative 'constants'

###########################
### ORDERS DATA OBJECTS ###
###########################
WorkingOrder = Struct.new(:id, :schwab_id, :status, :order_result, :details, :fill_time, :sent_time)

###########################
### MARKET DATA OBJECTS ###
###########################
class OptionsChain
  def initialize(underlying_price:, call_opts: [], put_opts: [])
    @underlying_price = underlying_price
    @call_opts = call_opts
    @put_opts = put_opts
  end

  attr_reader :call_opts, :put_opts, :underlying_price

  def get_option(symbol, contract_type)
    if contract_type == 'CALL'
      call_opts.find { |opt| opt.symbol == symbol }
    elsif contract_type == 'PUT'
      put_opts.find { |opt| opt.symbol == symbol }
    else
      nil
    end
  end
end

#############################
### STRATEGY DATA OBJECTS ###
#############################

class NullStrategy
  def quantity
    0
  end

  def expiration_date
    nil
  end

  def price
    0.0
  end

  def price_increment
    0.0
  end

  def nil?
    true
  end

  def to_h
    { type: StrategyTypes::NULL_STRATEGY }
  end
end

class StrategyBase
  def initialize(quantity: nil, expiration_date: nil, price_increment: 0.05)
    @quantity = quantity
    @expiration_date = expiration_date
    @price_increment = price_increment
  end

  attr_reader :quantity, :expiration_date, :price, :price_increment

  def price_rounded_up_by_increment
    # NOTE: subclass must implement price method
    ((price / price_increment).ceil * price_increment).round(2)
  end

  def price_rounded_down_by_increment
    # NOTE: subclass must implement price method
    ((price / price_increment).floor * price_increment).round(2)
  end

  def to_h(**kwargs)
    {
      quantity: quantity,
      expiration_date: expiration_date,
      price_increment: price_increment
    }
  end
end

class IronCondor < StrategyBase
  def initialize(put_spread:, call_spread:, **kwargs)
    super(**kwargs)
    @put_spread = put_spread
    @call_spread = call_spread
  end

  attr_reader :put_spread, :call_spread

  def price
    put_spread.price + call_spread.price
  end

  def to_h
    super.merge(
      {
        type: StrategyTypes::IRON_CONDOR,
        put_spread: put_spread.to_h(with_contract_dtls: false),
        call_spread: call_spread.to_h(with_contract_dtls: false)
      }
    )
  end
end

class VerticalSpread < StrategyBase
  def initialize(short_leg:, long_leg:, contract_type:, **kwargs)
    super(**kwargs)
    @short_leg = short_leg
    @long_leg = long_leg
    @contract_type = contract_type
  end

  attr_reader :short_leg, :long_leg, :contract_type

  def delta
    short_leg.delta.abs
  end

  def symbols
    [short_leg.symbol, long_leg.symbol]
  end

  def price
    (short_leg.mark - long_leg.mark).abs
  end

  def price_rounded_down_by_increment
    ((price / price_increment).floor * price_increment).round(2)
  end

  def price_rounded_up_by_increment
    ((price / price_increment).ceil * price_increment).round(2)
  end

  def spread_width
    (long_leg.strike - short_leg.strike).abs
  end

  def to_h(with_contract_dtls: true)
    if with_contract_dtls
      super.merge(
        {
          type: StrategyTypes::VERTICAL_SPREAD,
          contract_type: contract_type,
          short_leg: short_leg.to_h(with_contract_dtls: false),
          long_leg: long_leg.to_h(with_contract_dtls: false)
        }
      )
    else
      {
        type: StrategyTypes::VERTICAL_SPREAD,
        contract_type: contract_type,
        short_leg: short_leg.to_h(with_contract_dtls: false),
        long_leg: long_leg.to_h(with_contract_dtls: false)
      }
    end
  end
end

class OptionLeg < StrategyBase
  def initialize(
    symbol:,
    contract_type:,
    strike: nil,
    mark: nil,
    delta: nil,
    gamma: nil,
    theta: nil,
    vega: nil,
    rho: nil,
    volume: nil,
    open_interest: nil,
    **kwargs
  )
    super(**kwargs)
    @symbol = symbol
    @strike = strike
    @mark = mark
    @delta = delta
    @gamma = gamma
    @theta = theta
    @vega = vega
    @rho = rho
    @volume = volume
    @open_interest = open_interest
    @contract_type = contract_type
  end

  attr_reader :symbol, :strike, :mark, :delta, :contract_type, :gamma, :theta, :vega, :rho, :volume, :open_interest

  def price
    mark
  end

  def to_h(with_contract_dtls: true)
    if with_contract_dtls
      super.merge(
        {
          symbol: symbol,
          strike: strike,
          mark: mark,
          delta: delta,
          gamma: gamma,
          theta: theta,
          vega: vega,
          rho: rho,
          volume: volume,
          open_interest: open_interest,
          contract_type: contract_type
        }
      )
    else
      {
        symbol: symbol,
        strike: strike,
        mark: mark,
        delta: delta,
        gamma: gamma,
        theta: theta,
        vega: vega,
        rho: rho,
        volume: volume,
        open_interest: open_interest,
        contract_type: contract_type
      }
    end
  end
end
