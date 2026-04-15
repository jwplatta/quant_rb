# frozen_string_literal: true

class SpxwIronCondorExampleBase < QuantRb::Strategy
  TARGET_ABS_DELTA = 0.10
  TARGET_WING_WIDTH = 50.0
  ENTRY_HOUR_UTC = 15
  ENTRY_MINUTE_UTC = 0
  EXIT_HOUR_UTC = 19
  EXIT_MINUTE_UTC = 30

  def initialize
    set_start_date(self.class::START_DATE.year, self.class::START_DATE.month, self.class::START_DATE.day)
    set_end_date(self.class::END_DATE.year, self.class::END_DATE.month, self.class::END_DATE.day)
    set_cash(100_000)

    @spx = add_index("SPX", resolution: :minute)
    @spxw = add_index_option("SPX", "SPXW", resolution: :minute) do |expiry|
      expiry == self.class::OPTION_EXPIRY
    end

    @opened_ticket = nil
    @opened_legs = nil
    @closed = false
  end

  def on_data(slice)
    if should_open_position?(slice.time)
      chain = slice.option_chains.dig(@spxw, self.class::OPTION_EXPIRY)
      open_condor(chain) if chain
    end

    return unless should_close_position?(slice.time)

    chain = slice.option_chains.dig(@spxw, self.class::OPTION_EXPIRY)
    close_condor(chain) if chain
  end

  private

  def should_open_position?(current_time)
    return false if @opened_ticket
    current_time >= utc_time_for(current_time.to_date, ENTRY_HOUR_UTC, ENTRY_MINUTE_UTC)
  end

  def should_close_position?(current_time)
    return false unless @opened_ticket
    return false if @closed
    return false unless portfolio.positions[@opened_ticket.order_id]

    current_time >= utc_time_for(current_time.to_date, EXIT_HOUR_UTC, EXIT_MINUTE_UTC)
  end

  def open_condor(chain)
    @opened_legs = select_condor(chain)
    return unless @opened_legs

    credit = opening_credit(@opened_legs)
    return unless credit && credit.positive?

    @opened_ticket = combo_limit_order(order_legs(@opened_legs), 1, credit.round(2))
  end

  def close_condor(chain)
    debit = closing_debit(chain, @opened_legs)
    return unless debit

    portfolio.close_position(
      @opened_ticket.order_id,
      debit.round(4),
      time,
      strategy_class: self.class,
      notes: "#{self.class::SOURCE_LABEL} SPXW iron condor example"
    )
    @closed = true
  end

  def select_condor(chain)
    puts = eligible_options(chain.put_opts, side: :put)
    calls = eligible_options(chain.call_opts, side: :call)

    short_put = nearest_delta_option(puts)
    short_call = nearest_delta_option(calls)
    return nil unless short_put && short_call

    long_put = wing_option(puts, short_put, side: :put)
    long_call = wing_option(calls, short_call, side: :call)
    return nil unless long_put && long_call

    {
      short_put: short_put,
      long_put: long_put,
      short_call: short_call,
      long_call: long_call
    }
  end

  def eligible_options(options, side:)
    options.select do |option|
      next false unless option.delta && option.bid && option.ask
      next false unless option.bid.positive? && option.ask.positive?

      side == :put ? option.delta.negative? : option.delta.positive?
    end
  end

  def nearest_delta_option(options)
    options.min_by { |option| (option.delta.abs - TARGET_ABS_DELTA).abs }
  end

  def wing_option(options, short_leg, side:)
    candidates = options.select do |option|
      width =
        if side == :put
          short_leg.strike - option.strike
        else
          option.strike - short_leg.strike
        end

      width.positive?
    end

    candidates.min_by do |option|
      width =
        if side == :put
          short_leg.strike - option.strike
        else
          option.strike - short_leg.strike
        end

      (width - TARGET_WING_WIDTH).abs
    end
  end

  def opening_credit(legs)
    short_put = legs.fetch(:short_put)
    long_put = legs.fetch(:long_put)
    short_call = legs.fetch(:short_call)
    long_call = legs.fetch(:long_call)

    short_put.bid + short_call.bid - long_put.ask - long_call.ask
  end

  def closing_debit(chain, opened_legs)
    current = opened_legs.each_with_object({}) do |(name, option), memo|
      memo[name] = chain.all_options.find { |candidate| candidate.symbol == option.symbol }
    end
    return nil if current.values.any?(&:nil?)

    current.fetch(:short_put).ask + current.fetch(:short_call).ask -
      current.fetch(:long_put).bid - current.fetch(:long_call).bid
  end

  def order_legs(legs)
    [
      { symbol: legs.fetch(:short_put).symbol, quantity: -1 },
      { symbol: legs.fetch(:long_put).symbol, quantity: 1 },
      { symbol: legs.fetch(:short_call).symbol, quantity: -1 },
      { symbol: legs.fetch(:long_call).symbol, quantity: 1 }
    ]
  end

  def utc_time_for(date, hour, minute)
    Time.utc(date.year, date.month, date.day, hour, minute, 0)
  end
end

class SyntheticSpxwIronCondorExample < SpxwIronCondorExampleBase
  START_DATE = Date.new(2026, 4, 14)
  END_DATE = Date.new(2026, 4, 14)
  OPTION_EXPIRY = Date.new(2026, 4, 15)
  SOURCE_LABEL = "synthetic"
end

class SampledSpxwIronCondorExample < SpxwIronCondorExampleBase
  START_DATE = Date.new(2026, 4, 14)
  END_DATE = Date.new(2026, 4, 14)
  OPTION_EXPIRY = Date.new(2026, 4, 15)
  SOURCE_LABEL = "sampled"
end
