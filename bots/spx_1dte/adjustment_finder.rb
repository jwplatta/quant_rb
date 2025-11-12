# NOTES:
# 1. Find target strikes by delta
# 2. Calculate costs to close and open the new spread on the tested side
#   - If the short leg is greater than the 20 delta, then should for that
# 3. Calculate costs to close and open the new spread on the untested side
# 4. Tweak the spread strikes to balanced the costs as best as possible
# 14.4 - 8.0 = 6.4 debit
# 5.1 - 2.25 = 2.85 credit
require_relative 'data_objects'
require_relative 'util'
require_relative 'iron_condor_trade'

class AdjustmentFinder
  # NOTE: expects a vertical spread for both tested and untested sides
  def initialize(
    tested_spread:,
    untested_spread:,
    underlying_symbol:,
    option_root:,
    markets:,
    contracts:,
    est_fees:,
    est_commissions:,
    price_increment:,
    target_delta: nil,
    untested_max_delta: nil,
    spread_price_ratio: 1.0,
    max_search_attempts: 3,
    max_tweak_attempts: 100,
    logger: nil
  )
    @tested_spread = tested_spread
    @untested_spread = untested_spread
    @expiration_date = tested_spread.short_leg.expiration_date
    @spread_width = tested_spread.spread_width
    @underlying_symbol = underlying_symbol
    @option_root = option_root
    @markets = markets
    @contracts = contracts
    @est_fees = est_fees
    @est_commissions = est_commissions
    @target_delta = target_delta
    @untested_max_delta = untested_max_delta
    @spread_price_ratio = spread_price_ratio
    @price_increment = price_increment
    @max_search_attempts = max_search_attempts
    @max_tweak_attempts = max_tweak_attempts
    @logger = logger
  end

  attr_reader :tested_spread, :untested_spread, :expiration_date, :spread_width, :underlying_symbol, :option_root,
    :markets, :contracts, :target_delta, :untested_max_delta, :est_fees, :est_commissions, :spread_price_ratio,
    :price_increment, :max_search_attempts, :max_tweak_attempts, :logger

  def search
    @options_chain = nil
    valid_strategy_found = false
    tweak_attempts = 0

    # NOTE: start with the target delta for the tested side
    # and start with the strike moved up 5 points for the untested side
    new_tested_spread = find_spread_by_delta(target_delta, spread_width, tested_spread.contract_type)
    new_untested_spread = move_spread_up(untested_spread, untested_spread.contract_type, 5)

    while !valid_strategy_found && tweak_attempts < max_tweak_attempts
      puts "NEW TESTED SPREAD #{new_tested_spread.short_leg.contract_type}: #{new_tested_spread.short_leg.strike}/#{new_tested_spread.long_leg.strike} " \
           "PRICE: #{new_tested_spread.price} DELTA: #{new_tested_spread.delta}"
      puts "NEW UNTESTED SPREAD #{new_untested_spread.short_leg.contract_type}: #{new_untested_spread.short_leg.strike}/#{new_untested_spread.long_leg.strike} " \
           "PRICE: #{new_untested_spread.price} DELTA: #{new_untested_spread.delta}"
      tweak_attempts += 1


      if new_untested_spread.delta.abs > untested_max_delta
        puts "Untested spread delta #{new_untested_spread.delta} above max #{untested_max_delta}. Moving untested spread away."
        new_untested_spread = move_spread_away(new_untested_spread, new_untested_spread.contract_type, 5)
        new_tested_spread = move_spread_up(new_tested_spread, new_tested_spread.contract_type, 5)
      elsif !cover_rollaway_cost?(untested_spread, new_untested_spread, tested_spread, new_tested_spread)
        puts "Could not cover roll away cost. Moving untested spread up."
        new_untested_spread = move_spread_up(new_untested_spread, untested_spread.contract_type, 5)
      elsif new_tested_spread.short_leg.strike == tested_spread.short_leg.strike
        raise StandardError, "Tested spread not moved from original position. Moving untested spread up."
      else
        valid_strategy_found = true
      end
      puts "---"
      # is the credit for the roll up greater than the cost of the roll away?
      #   then roll away the tested side further
      # can we cover cost of the roll away? (i.e. are we meeting the spread_price_ratio?)
      #   then not move up the untested side again
      # is the untested side delta above the max delta?
      #   then move away the untested side
      # is the tested side delta below the target delta?
      #   then move away the tested side
      # else
      #   valid_strategy_found = true
    end

    binding.pry
    [new_tested_spread, new_untested_spread]
  end

  def cover_rollaway_cost?(untested_spread, new_untested_spread, tested_spread, new_tested_spread)
    roll_price(untested_spread, new_untested_spread) >= roll_price(tested_spread, new_tested_spread).abs * spread_price_ratio
  end

  def roll_price(old_spread, new_spread)
    (new_spread.price - old_spread.price) * 100 * contracts - est_fees * contracts - est_commissions * contracts
  end

  def move_spread_away(spread, contract_type, points)
    # NOTE: away from ATM
    new_short_strike = if contract_type == 'CALL'
      spread.short_leg.strike + points
    else
      spread.short_leg.strike - points
    end

    find_spread(new_short_strike, spread.spread_width, contract_type)
  end

  def move_spread_up(spread, contract_type, points)
    # NOTE: up towards ATM
    new_short_strike = if contract_type == 'CALL'
      spread.short_leg.strike - points
    else
      spread.short_leg.strike + points
    end

    find_spread(new_short_strike, spread.spread_width, contract_type)
  end

  def find_spread_by_delta(target_delta, spread_width, contract_type)
    opts = if contract_type == 'CALL'
              options_chain.call_opts
            else
              options_chain.put_opts
            end

    best_opt = opts.select { |o| o.delta }.min_by { |o| (o.delta.abs.to_f - target_delta.to_f).abs }
    raise StandardError, "Cannot find option with target delta" unless best_opt

    short_leg = new_option_leg(best_opt.symbol, best_opt.strike, best_opt.mark, best_opt.delta, contract_type, best_opt.expiration_date)
    short_strike = best_opt.strike

    long_leg = if contract_type == 'CALL'
      opts.find { |opt| opt.strike == short_strike + spread_width }.then do |opt|
        new_option_leg(opt.symbol, opt.strike, opt.mark, opt.delta, contract_type, opt.expiration_date)
      end
    else
      opts.find { |opt| opt.strike == short_strike - spread_width }.then do |opt|
        new_option_leg(opt.symbol, opt.strike, opt.mark, opt.delta, contract_type, opt.expiration_date)
      end
    end

    VerticalSpread.new(short_leg, long_leg, contract_type)
  end

  def find_spread(short_strike, spread_width, contract_type)
    long_strike = if contract_type == 'CALL'
                    short_strike + spread_width
                  else
                    short_strike - spread_width
                  end
    opts = if contract_type == 'CALL'
              options_chain.call_opts
            else
              options_chain.put_opts
            end

    short_leg = opts.find { |opt| opt.strike == short_strike }.then do |opt|
      new_option_leg(opt.symbol, opt.strike, opt.mark, opt.delta, contract_type, opt.expiration_date)
    end
    long_leg = opts.find { |opt| opt.strike == long_strike }.then do |opt|
      new_option_leg(opt.symbol, opt.strike, opt.mark, opt.delta, contract_type, opt.expiration_date)
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

    if option_root.present?
      call_opts = opt_chain.call_opts.select { |opt| opt.option_root == option_root }
      put_opts = opt_chain.put_opts.select { |opt| opt.option_root == option_root }
      @options_chain = OptionsChain.new(
        underlying_price: opt_chain.underlying_price,
        call_opts: call_opts,
        put_opts: put_opts
      )
    else
      @options_chain = OptionsChain.new(
        underlying_price: opt_chain.underlying_price,
        call_opts: opt_chain.call_opts,
        put_opts: opt_chain.put_opts
      )
    end
  end

  def roll_away_price(new_short_leg_symbol:, new_long_leg_symbol:, old_short_leg_symbol:, old_long_leg_symbol:, contract_type:)
    # so you will need to get the current market prices from the option chain or by making a separate call
    close_price = close_price(
      short_leg_symbol: old_short_leg_symbol,
      long_leg_symbol: old_long_leg_symbol,
      contract_type: contract_type
    )
    open_price = open_price(
      short_leg_symbol: new_short_leg_symbol,
      long_leg_symbol: new_long_leg_symbol,
      contract_type: contract_type
    )
    # NOTE: will be a debit
    close_price - open_price
  end

  def roll_up_price(new_short_leg_symbol:, new_long_leg_symbol:, old_short_leg_symbol:, old_long_leg_symbol:, contract_type:)
    close_price = close_price(
      short_leg_symbol: old_short_leg_symbol,
      long_leg_symbol: old_long_leg_symbol,
      contract_type: contract_type
    )
    open_price = open_price(
      short_leg_symbol: new_short_leg_symbol,
      long_leg_symbol: new_long_leg_symbol,
      contract_type: contract_type
    )
    # NOTE: will be a credit
    open_price - close_price
  end

  def close_price(short_leg_symbol:, long_leg_symbol:, contract_type:)
    # so you will need to get the current market prices from the option chain or by making a separate call
    short_leg = options_chain.get_option(short_leg_symbol, contract_type)
    long_leg = options_chain.get_option(long_leg_symbol, contract_type)

    # NOTE: you will be buying this spread back. So this is a debit.
    round_up_to_nearest(long_leg.mark - short_leg.mark, price_increment)
  end

  def open_price(short_leg_symbol:, long_leg_symbol:, contract_type:)
    short_leg = options_chain.get_option(short_leg_symbol, contract_type)
    long_leg = options_chain.get_option(long_leg_symbol, contract_type)

    # NOTE: you will be selling this spread. So this is a credit.
    round_down_to_nearest(short_leg.mark - long_leg.mark, price_increment)
  end

  def new_option_leg(symbol, strike, mark, delta, contract_type, expiration_date)
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
