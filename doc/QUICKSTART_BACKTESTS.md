# QuantRb Quickstart: Simple Backtests

This guide shows the smallest useful path to running a backtest with `quant_rb`.

## 1. Point QuantRb At Your Data

`quant_rb` reads candle and options data from a configurable root path.

Minimal example:

```ruby
QuantRb.configure do |config|
  config.data_path = File.expand_path("~/.tickrake/data")
  config.history_subpath = "history/schwab"
  config.options_subpath = "options/schwab"
end
```

For a simple equity backtest, the important part is that candle history exists under the configured history path.

## 2. Define A Strategy

Strategies inherit from `QuantRb::Strategy`.

At minimum:

- set a start date
- set an end date
- set starting cash
- subscribe to at least one symbol
- implement `on_data`

Example:

```ruby
require_relative "../lib/quant_rb"

class BuyAndSellSpy < QuantRb::Strategy
  def initialize
    set_start_date(2024, 1, 2)
    set_end_date(2024, 1, 2)
    set_cash(10_000)
    @spy = add_equity("SPY", resolution: :minute)
  end

  def on_data(slice)
    return unless slice.bars[@spy]

    market_order(@spy, 1) if time == Time.parse("2024-01-02 14:31:00 UTC")
    market_order(@spy, -1) if time == Time.parse("2024-01-02 14:32:00 UTC")
  end
end
```

## 3. Run The Backtest

```ruby
result = QuantRb::BacktestEngine.run(BuyAndSellSpy, progress: false)

puts result.summary
result.trades.each { |trade| p trade.to_h }
```

The return value is a `QuantRb::Reporting::BacktestResult`.

Useful fields:

- `result.initial_cash`
- `result.final_portfolio_value`
- `result.trades`
- `result.metrics`

## 4. Full Minimal Script

```ruby
require_relative "../lib/quant_rb"

QuantRb.configure do |config|
  config.data_path = File.expand_path("~/.tickrake/data")
  config.history_subpath = "history/schwab"
end

class BuyAndSellSpy < QuantRb::Strategy
  def initialize
    set_start_date(2024, 1, 2)
    set_end_date(2024, 1, 2)
    set_cash(10_000)
    @spy = add_equity("SPY", resolution: :minute)
  end

  def on_data(slice)
    return unless slice.bars[@spy]

    market_order(@spy, 1) if time == Time.parse("2024-01-02 14:31:00 UTC")
    market_order(@spy, -1) if time == Time.parse("2024-01-02 14:32:00 UTC")
  end
end

result = QuantRb::BacktestEngine.run(BuyAndSellSpy, progress: false)
puts result.summary
```

## 5. Adding Execution Realism

If you want something more realistic than the broker defaults, inject a backtest broker with explicit reality models:

```ruby
broker = QuantRb::Brokers::BacktestBroker.new(
  fill_model: QuantRb::Reality::BidAskFillModel.new,
  slippage_model: QuantRb::Reality::ConstantSlippageModel.new(amount: 0.05),
  transaction_fee_model: QuantRb::Reality::PerSpreadTransactionFeeModel.new(
    option_fee_per_spread: 1.14,
    option_commission_per_spread: 1.30
  )
)

result = QuantRb::BacktestEngine.run(BuyAndSellSpy, broker: broker, progress: false)
```

The broker applies these models when pending orders are processed on each time step.

## 6. Running Option Strategies

For option strategies, subscribe with `add_index_option`:

```ruby
@spx = add_index("SPX", resolution: :minute)
@spxw = add_index_option("SPX", "SPXW", resolution: :minute)
```

Then read chains from `slice.option_chains[@spxw]` and submit combo orders with `combo_limit_order`.

See:

- [BACKTEST_ENGINE.md](./BACKTEST_ENGINE.md)
- [spxw_ic_backtest.rb](../scripts/quant_rb/spxw_ic_backtest.rb)

## 7. Common Gotchas

- You must subscribe to at least one candle symbol. The first candle subscription drives the backtest clock.
- `on_data` only sees data available at the current timestamp.
- Orders are submitted by the strategy, but filled later by the broker during the engine loop.
- Direct calls to `portfolio.close_position(...)` bypass broker-managed fills and slippage.
