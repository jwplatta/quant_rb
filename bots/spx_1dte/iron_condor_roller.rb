require_relative 'data_objects'
require_relative 'util'
require_relative 'iron_condor_trade'

class IronCondorRoller
  def initialize(
    underlying_symbol:,
    option_root:,
    spread_width:,
    contracts: 1,
    max_delta: nil,
    cost_coverage_perc: 1.0,
    est_fees: 0.0,
    est_commissions: 0.0,
    price_increment: 0.05,
    max_search_attempts: 3,
    markets: nil,
    logger: nil
  )
    # option chain parameters
    @underlying_symbol = underlying_symbol
    @option_root = option_root
    @expiration_date = nil

    # spread
    @spread_width = spread_width
    @max_delta = max_delta
    @contracts = contracts

    # price
    @cost_coverage_perc = cost_coverage_perc
    @est_fees = est_fees
    @est_commissions = est_commissions
    @price_increment = price_increment

    # search
    @_search_attempts = 0
    @max_search_attempts = max_search_attempts

    # dependencies
    @markets = markets
    @logger = logger
  end

  attr_reader :underlying_symbol, :option_root, :expiration_date,
    :spread_width, :contracts, :max_delta,
    :est_fees, :est_commissions, :price_increment, :cost_coverage_perc,
    :max_search_attempts, :max_tweak_attempts,
    :markets, :logger

  def search(tested_spread:, untested_spread:, move_size: 5)
    @options_chain = nil
    @expiration_date = tested_spread.short_leg.expiration_date

    new_tested_spread = move_spread_away(tested_spread, tested_spread.contract_type, move_size)
    new_untested_spread = move_spread_up(untested_spread, untested_spread.contract_type, move_size)

    while new_untested_spread.delta <= max_delta
      rollaway_cost = roll_price(tested_spread, new_tested_spread).abs
      rollup_credit = roll_price(untested_spread, new_untested_spread)

      if rollaway_cost * cost_coverage_perc > rollup_credit
        new_untested_spread = move_spread_up(
          new_untested_spread,
          new_untested_spread.contract_type,
          5
        )
      elsif rollaway_cost * cost_coverage_perc <= rollup_credit
        @_search_attempts = 0
        return [new_tested_spread, new_untested_spread]
      end
    end

    if @_search_attempts < max_search_attempts
      @_search_attempts += 1
      sleep(5)
      search(tested_spread: tested_spread, untested_spread: untested_spread, move_size: move_size)
    else
      # REVIEW: need to handle this gracefully. Right now forcing the bot to crash.
      @_search_attempts = 0
      [nil, nil]
    end
  end

  def roll_price(old_spread, new_spread)
    round_down_to_nearest((new_spread.price - old_spread.price), price_increment) * 100 * contracts - est_fees * contracts - est_commissions * contracts
  end

  def move_spread_away(spread, contract_type, points)
    # NOTE: away from ATM
    short_strike = if contract_type == 'CALL'
      spread.short_leg.strike + points
    else
      spread.short_leg.strike - points
    end
    long_strike = if contract_type == 'CALL'
      short_strike + spread.spread_width
    else
      short_strike - spread.spread_width
    end

    build_spread(short_strike, long_strike, contract_type)
  end

  def move_spread_up(spread, contract_type, points)
    # NOTE: up towards ATM
    short_strike = if contract_type == 'CALL'
      spread.short_leg.strike - points
    else
      spread.short_leg.strike + points
    end

    long_strike = if contract_type == 'CALL'
      short_strike + spread.spread_width
    else
      short_strike - spread.spread_width
    end

    build_spread(short_strike, long_strike, contract_type)
  end

  def build_spread(short_strike, long_strike, contract_type)
    opts = if contract_type == 'CALL'
      options_chain.call_opts
    else
      options_chain.put_opts
    end

    short_leg = opts.find { |opt| opt.strike == short_strike }.then do |opt|
      build_leg(opt.symbol, opt.strike, opt.mark, opt.delta, contract_type, opt.expiration_date)
    end
    long_leg = opts.find { |opt| opt.strike == long_strike }.then do |opt|
      build_leg(opt.symbol, opt.strike, opt.mark, opt.delta, contract_type, opt.expiration_date)
    end

    VerticalSpread.new(short_leg, long_leg, contract_type)
  end

  def options_chain
    return @options_chain if @options_chain

    opt_chain = markets.get_option_chain(
      underlying_symbol,
      contract_type: 'ALL',
      strike_range: 'ALL',
      to_date: expiration_date,
      from_date: expiration_date
    )

    @options_chain = OptionsChain.new(
      underlying_price: opt_chain.underlying_price,
      call_opts: option_root.present? ? opt_chain.call_opts.select { |opt| opt.option_root == option_root } : opt_chain.call_opts,
      put_opts: option_root.present? ? opt_chain.put_opts.select { |opt| opt.option_root == option_root } : opt_chain.put_opts
    )
  end

  def build_leg(symbol, strike, mark, delta, contract_type, expiration_date)
    OptionLeg.new(
      symbol,
      strike,
      mark,
      delta,
      contract_type,
      expiration_date
    )
  end
end
