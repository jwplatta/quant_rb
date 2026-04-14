# QuantRb Getting Started

## Overview

`quant_rb` is a backtesting engine for event-driven trading strategies. A typical workflow is:

1. Point the engine at a local market-data root.
2. Write a strategy by inheriting from `QuantRb::Strategy`.
3. Run the strategy with `QuantRb::BacktestEngine.run`.
4. Inspect the returned `BacktestResult` for trades and metrics.

## Data Layout

`quant_rb` reads data from a configurable root path.

Default layout:

```text
~/.tickrake/data/
  history/
    schwab/
      SPY/
        SPY_1min.csv
  options/
    schwab/
      SPXW_exp2025-12-18_2025-12-18_13-50-58.csv
```

The current Phase 5a example only needs equity candle data:

```text
~/.tickrake/data/history/schwab/SPY/SPY_1min.csv
```

## Minimal Usage

```ruby
require "quant_rb"

class MyStrategy < QuantRb::Strategy
  def initialize
    set_start_date(2024, 1, 1)
    set_end_date(2024, 12, 31)
    set_cash(100_000)
    @spy = add_equity("SPY", resolution: :minute)
  end

  def on_data(slice)
    return unless slice.bars[@spy]
  end
end

QuantRb.configure do |config|
  config.data_path = File.expand_path("~/.tickrake/data")
end

result = QuantRb::BacktestEngine.run(MyStrategy)
puts result.summary
```

## Examples

- [Examples Index](./examples/README.md)
- [SPY SMA Crossover Guide](./examples/spy_sma_crossover.md)
- Runnable example script: [examples/spy_sma_crossover_backtest.rb](../examples/spy_sma_crossover_backtest.rb)

## Notes

- `QuantRb::BacktestEngine.run` returns a `QuantRb::Reporting::BacktestResult`.
- `result.trades` contains completed trades.
- `result.metrics.to_h` exposes aggregate performance metrics.
