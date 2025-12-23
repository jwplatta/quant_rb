require_relative 'data_objects'

class IronCondorFinder
  def initialize(
    underlying_symbol,
    markets,
    option_root: nil,
    spread_width: 10,
    max_credit: 1.5,
    max_put_delta: 0.1,
    min_put_delta: 0.03,
    max_call_delta: 0.1,
    min_call_delta: 0.03,
    max_total_delta: 0.15,
    min_credit: 1.05,
    credit_balance_ratio: 0.8,
    delta_ratio: 0.7,
    quantity: 1,
    price_increment: 0.05,
    max_search_attempts: 3,
    max_tweak_attempts: 100,
    logger: nil
  )
    @underlying_symbol = underlying_symbol
    @option_root = option_root
    @markets = markets
    @options_chain = nil
    @spread_width = spread_width
    @max_credit = max_credit
    @min_credit = min_credit
    @credit_balance_ratio = credit_balance_ratio
    @max_call_delta = max_call_delta
    @min_call_delta = min_call_delta
    @max_put_delta = max_put_delta
    @min_put_delta = min_put_delta
    @max_total_delta = max_total_delta
    @delta_ratio = delta_ratio
    @max_tweak_attempts = 100
    @max_search_attempts = max_search_attempts
    @search_attempts = 0
    @quantity = quantity
    @price_increment = price_increment
    @expiration_date = nil
    @logger = logger
  end

  attr_reader :underlying_symbol, :option_root, :markets,
    :spread_width,
    :credit_balance_ratio, :delta_ratio, :max_search_attempts,
    :max_credit, :min_credit,
    :max_call_delta, :min_call_delta,
    :max_put_delta, :min_put_delta,
    :max_total_delta,
    :max_tweak_attempts,
    :quantity, :price_increment,
    :logger

  def search(expiration_date: nil)
    @expiration_date = expiration_date
    logger.info "Find new trade #{underlying_symbol} for expiration date #{@expiration_date}"
    @options_chain = nil

    valid_strategy_found = false
    call_spread, put_spread = find_init_strategy
    tweak_attempts = 0

    # NOTE: tweak strategy until it meets criteria
    while !valid_strategy_found
      # What to check:
      # does the strategy meet min credit?
      # does the strategy have enough credit to reduce the risk?
      # is the strategy price lopsided?
      # are the deltas on each side acceptable?
      tweak_attempts += 1
      strategy_price = call_spread.price + put_spread.price

      if tweak_attempts >= max_tweak_attempts
        logger.warn "Could not find valid strategy after #{tweak_attempts} attempts"
        break
      elsif strategy_price < min_credit
        logger.info "Attempt ##{tweak_attempts}: Strategy credit low #{strategy_price.round(2)} < #{min_credit}"

        if call_spread.price < put_spread.price
          call_spread = move_spread_up(call_spread, 'CALL', 5)
        elsif put_spread.price < call_spread.price
          put_spread = move_spread_up(put_spread, 'PUT', 5)
        end
      elsif strategy_price > max_credit
        logger.info "Attempt ##{tweak_attempts}: Strategy credit high #{strategy_price.round(2)} > #{max_credit}"

        if call_spread.price > put_spread.price
          call_spread = move_spread_away(call_spread, 'CALL', 5)
        elsif put_spread.price > call_spread.price
          put_spread = move_spread_away(put_spread, 'PUT', 5)
        end
      elsif call_spread.delta > max_call_delta
        logger.info "Attempt ##{tweak_attempts}: Call spread delta high #{call_spread.delta} > #{max_call_delta}"
        call_spread = move_spread_away(call_spread, 'CALL', 5)
      elsif put_spread.delta > max_put_delta
        logger.info "Attempt ##{tweak_attempts}: Put spread delta high #{put_spread.delta} > #{max_put_delta}"
        put_spread = move_spread_away(put_spread, 'PUT', 5)
      elsif call_spread.delta + put_spread.delta > max_total_delta
        logger.info "Attempt ##{tweak_attempts}: Total strategy delta high: #{(call_spread.delta + put_spread.delta).round(2)} > #{max_total_delta}"
        if call_spread.delta > put_spread.delta
          call_spread = move_spread_away(call_spread, 'CALL', 5)
        else
          put_spread = move_spread_away(put_spread, 'PUT', 5)
        end
      elsif !credit_balanced?(call_spread, put_spread)
        logger.info "Attempt ##{tweak_attempts}: Strategy credit lopsided: #{call_spread.price} < #{put_spread.price}"

        if call_spread.price < put_spread.price
          call_spread = move_spread_up(call_spread, 'CALL', 5)
        elsif put_spread.price < call_spread.price
          put_spread = move_spread_up(put_spread, 'PUT', 5)
        end
      elsif !delta_balanced?(call_spread.delta, put_spread.delta)
        logger.info "Attempt ##{tweak_attempts}: Strategy delta lopsided: #{call_spread.delta.round(2)} < #{put_spread.delta.round(2)}"

        if call_spread.delta < put_spread.delta
          call_spread = move_spread_up(call_spread, 'CALL', 5)
          put_spread = move_spread_away(put_spread, 'PUT', 5)
        elsif put_spread.delta < call_spread.delta
          put_spread = move_spread_up(put_spread, 'PUT', 5)
          call_spread = move_spread_away(call_spread, 'CALL', 5)
        end
      else
        valid_strategy_found = true
      end
    end

    if valid_strategy_found
      iron_condor = IronCondor.new(
        put_spread: put_spread,
        call_spread: call_spread,
        expiration_date: @expiration_date,
        quantity: @quantity,
        price_increment: @price_increment,
      )

      logger.info "FinalStrategy(tweaks=#{tweak_attempts}) Underlying=#{options_chain.underlying_price} Straddle=#{straddle_price} CALL=#{iron_condor.call_spread.short_leg.strike}/#{iron_condor.call_spread.long_leg.strike} credit=#{iron_condor.call_spread.price} delta=#{iron_condor.call_spread.delta} | PUT=#{iron_condor.put_spread.short_leg.strike}/#{iron_condor.put_spread.long_leg.strike} credit=#{iron_condor.put_spread.price} delta=#{iron_condor.put_spread.delta} | TOTAL=#{iron_condor.price} TRADE_PRICE=#{iron_condor.price_rounded_down_by_increment}"

      iron_condor
    elsif @search_attempts <= @max_search_attempts
      logger.info "Could not find valid strategy. Try again in 5 seconds."
      @search_attempts += 1
      sleep(5)
      search(expiration_date: @expiration_date)
    else
      NullStrategy.new
    end
  end

  def options_chain
    return @options_chain if @options_chain

    opt_chain = markets.get_option_chain(
      underlying_symbol,
      contract_type: 'ALL',
      strike_range: 'OTM',
      to_date: @expiration_date,
      from_date: @expiration_date
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

  def find_init_strategy
    safe_call_strike = two_sig_strike('CALL')
    safe_put_strike = two_sig_strike('PUT')

    call_short_leg = options_chain.call_opts.find { |opt| opt.strike == safe_call_strike }.then do |opt|
      new_option_leg(opt.symbol, opt.strike, opt.mark, opt.delta, 'CALL')
    end
    call_long_leg = options_chain.call_opts.find { |opt| opt.strike == safe_call_strike + @spread_width }.then do |opt|
      new_option_leg(opt.symbol, opt.strike, opt.mark, opt.delta, 'CALL')
    end

    call_spread = new_spread(call_short_leg, call_long_leg, 'CALL')

    put_short_leg = options_chain.put_opts.find { |opt| opt.strike == safe_put_strike }.then do |opt|
      new_option_leg(opt.symbol, opt.strike, opt.mark, opt.delta, 'PUT')
    end
    put_long_leg = options_chain.put_opts.find { |opt| opt.strike == safe_put_strike - @spread_width }.then do |opt|
      new_option_leg(opt.symbol, opt.strike, opt.mark, opt.delta, 'PUT')
    end

    put_spread = new_spread(put_short_leg, put_long_leg, 'PUT')

    [call_spread, put_spread]
  end

  def credit_balanced?(call_spread, put_spread)
    smaller_credit = [call_spread.price, put_spread.price].min
    larger_credit = [call_spread.price, put_spread.price].max
    smaller_credit / larger_credit >= @credit_balance_ratio
  end

  def delta_balanced?(call_delta, put_delta)
    smaller_delta = [call_delta, put_delta].min
    larger_delta = [call_delta, put_delta].max
    smaller_delta / larger_delta >= @delta_ratio
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
      new_option_leg(opt.symbol, opt.strike, opt.mark, opt.delta, contract_type)
    end
    long_leg = opts.find { |opt| opt.strike == long_strike }.then do |opt|
      new_option_leg(opt.symbol, opt.strike, opt.mark, opt.delta, contract_type)
    end

    new_spread(short_leg, long_leg, contract_type)
  end

  def two_sig_strike(contract_type)
    raw_strike = if contract_type == 'CALL'
      options_chain.underlying_price + (2 * straddle_price)
    else
      options_chain.underlying_price - (2 * straddle_price)
    end

    (raw_strike / 5.0).round * 5
  end

  def straddle_price
    return @straddle_price if @straddle_price

    call_atm = options_chain.call_opts.min_by { |opt| (opt.strike - options_chain.underlying_price).abs }
    put_atm = options_chain.put_opts.min_by { |opt| (opt.strike - options_chain.underlying_price).abs }

    raise "No ATM call options found" if call_atm.nil? || put_atm.nil?

    @straddle_price = (call_atm.mark + put_atm.mark).round
  end

  def new_spread(short_leg, long_leg, contract_type)
    VerticalSpread.new(
      short_leg: short_leg,
      long_leg: long_leg,
      contract_type: contract_type
    )
  end

  def new_option_leg(symbol, strike, mark, delta, contract_type)
    OptionLeg.new(
      symbol: symbol,
      contract_type: contract_type,
      strike: strike,
      mark: mark,
      delta: delta
    )
  end
end
