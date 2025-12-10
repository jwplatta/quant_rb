require_relative 'data_objects'

class StrategyPricer
  def initialize(markets, logger)
    @markets = markets
    @logger = logger
  end
  attr_reader :markets, :logger

  def refresh(strategy)
    case strategy.class.name
    when 'IronCondor'
      new_iron_condor(strategy)
    when 'VerticalSpread'
      new_vertical_spread(strategy)
    else
      raise "Unsupported strategy type for price: #{strategy.class.name}"
    end
  rescue => e
    logger.error "Error getting strategy price: #{e.message}"
    raise e
  end

  private

  def new_iron_condor(strategy)
    short_call = markets.get_quote(strategy.call_spread.short_leg.symbol).then do |q|
      new_option_leg(q, 'CALL')
    end
    long_call = markets.get_quote(strategy.call_spread.long_leg.symbol).then do |q|
      new_option_leg(q, 'CALL')
    end
    short_put = markets.get_quote(strategy.put_spread.short_leg.symbol).then do |q|
      new_option_leg(q, 'PUT')
    end
    long_put = markets.get_quote(strategy.put_spread.long_leg.symbol).then do |q|
      new_option_leg(q, 'PUT')
    end

    put_spread = VerticalSpread.new(
      short_leg: short_put,
      long_leg: long_put,
      contract_type: 'PUT',
      quantity: strategy.put_spread.quantity,
      expiration_date: strategy.put_spread.expiration_date
    )
    call_spread = VerticalSpread.new(
      short_leg: short_call,
      long_leg: long_call,
      contract_type: 'CALL',
      quantity: strategy.call_spread.quantity,
      expiration_date: strategy.call_spread.expiration_date
    )

    IronCondor.new(
      put_spread: put_spread,
      call_spread: call_spread,
      quantity: strategy.quantity,
      expiration_date: strategy.expiration_date,
      price_increment: strategy.price_increment
    )
  end

  def new_vertical_spread(strategy)
    short_leg_quote = markets.get_quote(strategy.short_leg.symbol)
    long_leg_quote = markets.get_quote(strategy.long_leg.symbol)

    short_leg = new_option_leg(short_leg_quote, strategy.contract_type)
    long_leg = new_option_leg(long_leg_quote, strategy.contract_type)

    VerticalSpread.new(
      short_leg: short_leg,
      long_leg: long_leg,
      contract_type: strategy.contract_type,
      quantity: strategy.quantity,
      expiration_date: strategy.expiration_date,
      price_increment: strategy.price_increment
    )
  end

  def new_option_leg(quote, contract_type)
    OptionLeg.new(
      symbol: quote.symbol,
      contract_type: contract_type,
      strike: quote.strike_price,
      mark: quote.mark,
      delta: quote.delta,
      gamma: quote.gamma,
      theta: quote.theta,
      vega: quote.vega,
      rho: quote.rho,
      volume: quote.volume,
      open_interest: quote.open_interest,
      expiration_date: quote.expiration_date
    )
  end
end