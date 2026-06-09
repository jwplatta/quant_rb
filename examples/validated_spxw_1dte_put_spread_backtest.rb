# frozen_string_literal: true

require_relative "../lib/quant_rb"

RESOLUTION = :"5min"

class ValidatedSpxwOneDtePutSpreadExample < QuantRb::Strategy
  START_DATE = Date.iso8601(ENV.fetch("START_DATE", "2026-03-09"))
  END_DATE = Date.iso8601(ENV.fetch("END_DATE", "2026-03-31"))

  TARGET_PUT_DELTA = -0.05
  SPREAD_WIDTH = 20.0
  CONTRACTS = 1
  MAX_OPEN_SPREADS = 2
  ENTRY_HOUR_UTC = 20
  ENTRY_MINUTE_UTC = 30

  def initialize
    set_start_date(START_DATE.year, START_DATE.month, START_DATE.day)
    set_end_date(END_DATE.year, END_DATE.month, END_DATE.day)
    set_cash(100_000)

    @spx = add_index("SPX", resolution: RESOLUTION)
    @spxw = add_option_chain(
      "SPX",
      "SPXW",
      resolution: RESOLUTION,
      dataset: "schwab_samples"
    ) { |expiry| expiry == next_trading_day(time.to_date) }

    @open_spreads_by_expiry = {}
  end

  def on_data(slice)
    sync_open_position_state!
    open_position_if_needed(slice.option_chains[@spxw] || {})
  end

  private

  def open_position_if_needed(chains_by_expiry)
    return unless time >= utc_time_for(time.to_date, ENTRY_HOUR_UTC, ENTRY_MINUTE_UTC)
    return if @open_spreads_by_expiry.size >= MAX_OPEN_SPREADS

    expiry = next_trading_day(time.to_date)
    return if @open_spreads_by_expiry.key?(expiry)

    chain = chains_by_expiry[expiry]
    return unless chain

    short_put = select_short_put(chain)
    return unless short_put

    long_put = select_long_put(chain, short_put)
    return unless long_put

    credit = short_put.bid - long_put.ask
    return unless credit&.positive?

    limit_price = round_credit_limit(credit)
    ticket = combo_limit_order(
      order_legs(short_put:, long_put:),
      CONTRACTS,
      limit_price
    )
    @open_spreads_by_expiry[expiry] = {
      ticket: ticket,
      short_put: short_put,
      long_put: long_put
    }
    info("Opened validated sampled 1DTE SPXW put spread expiry=#{expiry} short=#{short_put.strike} long=#{long_put.strike} credit=#{limit_price}")
  end

  def select_short_put(chain)
    eligible_puts(chain).min_by { |option| (option.delta - TARGET_PUT_DELTA).abs }
  end

  def select_long_put(chain, short_put)
    eligible_puts(chain).find do |option|
      ((short_put.strike - option.strike) - SPREAD_WIDTH).abs < 0.001
    end
  end

  def eligible_puts(chain)
    chain.put_opts.select do |option|
      option.delta &&
        option.bid &&
        option.ask &&
        option.bid.positive? &&
        option.ask.positive? &&
        option.delta.negative?
    end.sort_by(&:strike)
  end

  def order_legs(short_put:, long_put:)
    [
      option_leg(short_put, quantity: -1),
      option_leg(long_put, quantity: 1)
    ]
  end

  def option_leg(option, quantity:)
    {
      symbol: option.symbol,
      quantity: quantity,
      expiration_date: option.expiration_date,
      strike: option.strike,
      put_call: option.put_call,
      underlying_symbol: option.underlying_symbol
    }
  end

  def utc_time_for(date, hour, minute)
    Time.utc(date.year, date.month, date.day, hour, minute, 0)
  end

  def next_trading_day(date)
    candidate = date + 1
    candidate += 1 while candidate.saturday? || candidate.sunday?
    candidate
  end

  def sync_open_position_state!
    @open_spreads_by_expiry.delete_if do |_expiry, spread|
      ticket = spread.fetch(:ticket)
      !portfolio.positions[ticket.order_id] && !pending_order?(ticket.order_id)
    end
  end

  def pending_order?(order_id)
    broker.respond_to?(:pending_orders) &&
      broker.pending_orders.any? { |order| order.id == order_id }
  end

  def round_credit_limit(price)
    ((price.to_f / 0.05).floor * 0.05).round(2)
  end
end

QuantRb.configure do |config|
  config.data_sources_config_path = ENV.fetch("QUANT_RB_DATA_SOURCES_CONFIG_PATH", QuantRb.config.data_sources_config_path)
  config.log_level = ENV.fetch("QUANT_RB_LOG_LEVEL", "info")
end

QuantRb.logger.info("Running validated sampled SPXW 1DTE put spread example")
QuantRb.logger.info("data_sources_config=#{QuantRb.config.data_sources_config_path} interval=#{RESOLUTION}")

result = QuantRb::BacktestEngine.run(ValidatedSpxwOneDtePutSpreadExample)

puts
puts result.summary
