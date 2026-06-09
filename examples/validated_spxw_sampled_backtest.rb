# frozen_string_literal: true

require_relative "../lib/quant_rb"

RESOLUTION = :"5min"
OPTIONS_PROVIDER = ENV.fetch("OPTIONS_PROVIDER", "schwab")
UNDERLYING_PROVIDER = ENV.fetch("UNDERLYING_PROVIDER", OPTIONS_PROVIDER)

class ValidatedSpxwSampledBacktestExample < QuantRb::Strategy
  START_DATE = Date.iso8601(ENV.fetch("START_DATE", "2025-01-01"))
  END_DATE = Date.iso8601(ENV.fetch("END_DATE", "2025-12-31"))

  CONTRACTS = 1
  ENTRY_HOUR_UTC = Integer(ENV.fetch("ENTRY_HOUR_UTC", "20"))
  ENTRY_MINUTE_UTC = Integer(ENV.fetch("ENTRY_MINUTE_UTC", "30"))

  def initialize
    set_start_date(START_DATE.year, START_DATE.month, START_DATE.day)
    set_end_date(END_DATE.year, END_DATE.month, END_DATE.day)
    set_cash(100_000)

    @spx = add_security("SPX", resolution: RESOLUTION, provider: UNDERLYING_PROVIDER)
    @spxw = add_option_chain(
      "SPX",
      "SPXW",
      resolution: RESOLUTION,
      provider: OPTIONS_PROVIDER
    )

    @opened_ticket = nil
  end

  def on_data(slice)
    return if @opened_ticket
    return unless time >= utc_time_for(time.to_date, ENTRY_HOUR_UTC, ENTRY_MINUTE_UTC)

    expiry, chain = next_available_chain(slice.option_chains[@spxw] || {})
    return unless chain

    short_call = chain.call_opts.find { |option| quoted?(option) && option.delta.to_f.positive? }
    short_put = chain.put_opts.find { |option| quoted?(option) && option.delta.to_f.negative? }
    return unless short_call && short_put

    limit_price = round_credit_limit(short_call.bid + short_put.bid)
    return unless limit_price.positive?

    @opened_ticket = combo_limit_order(
      [
        option_leg(short_call, quantity: -1),
        option_leg(short_put, quantity: -1)
      ],
      CONTRACTS,
      limit_price
    )
    info("Opened sampled SPXW strangle expiry=#{expiry} call=#{short_call.strike} put=#{short_put.strike} credit=#{limit_price}")
  end

  private

  def next_available_chain(chains_by_expiry)
    chains_by_expiry.sort_by { |expiry, _chain| expiry }.find { |_expiry, chain| !chain.empty? }
  end

  def quoted?(option)
    option.bid.to_f.positive? && option.ask.to_f.positive?
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

  def round_credit_limit(price)
    ((price.to_f / 0.05).floor * 0.05).round(2)
  end

  def utc_time_for(date, hour, minute)
    Time.utc(date.year, date.month, date.day, hour, minute, 0)
  end
end

QuantRb.configure do |config|
  config.log_level = ENV.fetch("QUANT_RB_LOG_LEVEL", "info")
end

QuantRb.logger.info("Running validated sampled SPXW example")
QuantRb.logger.info("options_provider=#{OPTIONS_PROVIDER} underlying_provider=#{UNDERLYING_PROVIDER} interval=#{RESOLUTION}")

result = QuantRb::BacktestEngine.run(ValidatedSpxwSampledBacktestExample)

puts
puts result.summary
