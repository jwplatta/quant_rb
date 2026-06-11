# frozen_string_literal: true

require_relative "../lib/quant_rb"

DATA_SOURCES_CONFIG = File.expand_path("data_sources.yml", __dir__)
RESOLUTION = :"5min"
MARKET_TIMEZONE = "America/Chicago"
START_DATE = Date.iso8601(ENV.fetch("START_DATE", "2022-01-01"))
END_DATE = Date.iso8601(ENV.fetch("END_DATE", "2023-01-01"))
TARGET_PUT_DELTA = -0.10
SPREAD_WIDTH = 20.0
CONTRACTS = 1
ENTRY_HOUR = 9
ENTRY_MINUTE = 35

class SyntheticSpxwZeroDtePutSpreadExample < QuantRb::Strategy
  def initialize
    set_start_date(START_DATE.year, START_DATE.month, START_DATE.day)
    set_end_date(END_DATE.year, END_DATE.month, END_DATE.day)
    set_market_timezone(MARKET_TIMEZONE)
    set_cash(100_000)

    @spx = add_index("SPX", resolution: RESOLUTION)
    @spxw = add_option_chain(
      "SPX",
      "SPXW",
      resolution: RESOLUTION,
      pricing_model: :black_scholes,
      dte: 0
    )

    @open_spreads_by_expiry = {}
  end

  def on_data(slice)
    sync_open_position_state!
    open_position_if_needed(slice.option_chains[@spxw] || {})
  end

  private

  def open_position_if_needed(chains_by_expiry)
    return unless morning_entry_window?

    expiry = market_date
    return if @open_spreads_by_expiry.key?(expiry)

    chain = chains_by_expiry[expiry]
    return unless chain

    short_put = select_short_put(chain)
    return unless short_put

    long_put = select_long_put(chain, short_put)
    return unless long_put

    credit = short_put.bid.to_f - long_put.ask.to_f
    return unless credit.positive?

    limit_price = round_credit_limit(credit)
    ticket = combo_limit_order(order_legs(short_put:, long_put:), CONTRACTS, limit_price)
    @open_spreads_by_expiry[expiry] = { ticket: ticket, short_put: short_put, long_put: long_put }

    info("Opened synthetic 0DTE SPXW put spread expiry=#{expiry} short=#{short_put.strike} long=#{long_put.strike} credit=#{limit_price}")
  end

  def morning_entry_window?
    current = market_time
    current.hour > ENTRY_HOUR || (current.hour == ENTRY_HOUR && current.min >= ENTRY_MINUTE)
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
    end.sort_by(&:strike).reverse
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
  config.data_sources_config_path = ENV.fetch("QUANT_RB_DATA_SOURCES_CONFIG_PATH", DATA_SOURCES_CONFIG)
  config.log_level = ENV.fetch("QUANT_RB_LOG_LEVEL", "info")
end

QuantRb.logger.info("Running synthetic SPXW 0DTE put spread example")
QuantRb.logger.info("data_sources_config=#{QuantRb.config.data_sources_config_path} period=#{START_DATE}..#{END_DATE} interval=#{RESOLUTION}")

result = QuantRb::BacktestEngine.run(SyntheticSpxwZeroDtePutSpreadExample)

puts
puts result.summary
