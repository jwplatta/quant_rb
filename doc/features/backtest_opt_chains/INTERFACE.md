# Interface

```ruby
class SpxwTargetDeltaIronCondorExampleBase < QuantRb::Strategy
  TARGET_CALL_DELTA = 0.05
  TARGET_PUT_DELTA = -0.05
  TARGET_WING_WIDTH = 20.0
  CONTRACTS = 1
  ENTRY_HOUR_UTC = 15
  ENTRY_MINUTE_UTC = 0
  EXIT_HOUR_UTC = 19
  EXIT_MINUTE_UTC = 30

  def initialize
    set_start_date(self.class::START_DATE.year, self.class::START_DATE.month, self.class::START_DATE.day)
    set_end_date(self.class::END_DATE.year, self.class::END_DATE.month, self.class::END_DATE.day)
    set_cash(100_000)

    @spx = add_index("SPX", resolution: :minute, provider: 'schwab')
    @vix = add_index_option("VIX", resolution: :minute, provider: 'ibkr-paper')
    @vix9d = add_index_option("VIX9D", resolution: :minute, provider: 'ibkr-paper')
    @vix1d = add_index_option("VIX1D", resolution: :minute, provider: 'ibkr-paper')

    # NOTE: here we want to interpolate the missing strikes and apply the binomail pricing model to backout the IV and calculate the greeks
    @spxw = add_index_option("SPX", "SPXW", resolution: :minute, provider: 'massive', interpolate: true, pricing_model: :binomial)

    # So we pass the VIX candles to use for the IV proxy and the underyling and use the black scholes model to calculate the prices and greeks
    @spxw = add_index_option("SPX", "SPXW", resolution: :minute, synthetic: true, underlying: "SPX", iv: { "ODTE": "VIX1D", "9DTE": "VIX9D", "30DTE": "VIX"}, pricing_mode: :black_scholes)

    # Schwab doesn't need any processing
    @spxw = add_index_option("SPX", "SPXW", resolution: :minute, provider: 'schwab')

    @opened_ticket = nil
    @opened_legs = nil
    @opened_expiry = nil
    @closed = false
  end
```

- And then underneatht the hood the quant_rb should be smart enough to either build the synethic chain based on the start and end dates and the frequency. Or it should should call the tickrake gem to fetch the data and then do whatever sort of processing it needs to do.
- In all three cases we should apply a no-arbitrage validator to ensure that the prices, greeks, IV and everything are all monotonic for both calls and puts.


Loading data with tickrake is easy. It returns an enumerator which contains hashes as rows
```ruby
# frozen_string_literal: true

require "date"
require_relative "../lib/tickrake"

loader = Tickrake::DataLoader.new

rows = loader.load_option_chains(
  provider: "schwab",
  ticker: "$SPX",
  option_root: "SPXW",
  expiration_date: Date.iso8601("2026-04-17"),
  start_date: Date.iso8601("2026-04-10"),
  end_date: Date.iso8601("2026-04-10"),
  frequency: "5min",
  include_metadata: true
).take(10)

puts "loaded #{rows.length} option rows"

data = rows.map do |row, index|
  row
end

### LOADING CANDLES

rows = loader.load_candles(
  provider: "ibkr-paper",
  ticker: "SPY",
  frequency: "1min",
  start_date: Date.iso8601("2026-04-10"),
  end_date: Date.iso8601("2026-04-10")
).take(10)

puts "loaded #{rows.length} candle rows"

rows.each_with_index do |row, index|
  puts [
    "row=#{index + 1}",
    "datetime=#{row["datetime"].iso8601}",
    "open=#{row["open"]}",
    "high=#{row["high"]}",
    "low=#{row["low"]}",
    "close=#{row["close"]}",
    "volume=#{row["volume"]}"
  ].join(" | ")
end
```