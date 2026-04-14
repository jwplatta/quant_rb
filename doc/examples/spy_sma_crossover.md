# SPY SMA Crossover

## Overview

This example shows a simple moving-average crossover strategy written against `QuantRb::Strategy`.

The strategy:

- subscribes to `SPY` minute candles
- computes a 10-period fast SMA and a 30-period slow SMA from the strategy's candle history
- enters long when the fast SMA crosses above the slow SMA
- exits when the fast SMA crosses below the slow SMA

The runnable script is [examples/spy_sma_crossover_backtest.rb](../../examples/spy_sma_crossover_backtest.rb).

## Required Data Layout

This example expects local candle data in the configured `quant_rb` data root.

With the default configuration, the required file is:

```text
~/.tickrake/data/history/schwab/SPY/SPY_1min.csv
```

If you want to use a different root path, set:

```bash
export QUANT_RB_DATA_PATH=/path/to/data/root
```

Optional overrides:

```bash
export QUANT_RB_HISTORY_SUBPATH=history/schwab
export QUANT_RB_OPTIONS_SUBPATH=options/schwab
```

## Running The Example

From the repository root:

```bash
ruby examples/spy_sma_crossover_backtest.rb
```

The script will:

1. load the `SpySmaCrossover` reference strategy from `doc/reference/spy_sma_crossover.rb`
2. configure `quant_rb` to read local data
3. run the backtest
4. print the summary and completed trades

## Strategy Source

The reference strategy implementation lives at [doc/reference/spy_sma_crossover.rb](../reference/spy_sma_crossover.rb).

That file is intentionally kept outside the gem load path. It is an example for users to copy and adapt, not part of the core `quant_rb` runtime API.
