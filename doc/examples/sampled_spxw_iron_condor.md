# Sampled SPXW Iron Condor

## Overview

This example runs the same basic `SPXW` iron condor strategy against **real sampled** option chain files from your local tickrake data folder.

The strategy:

- subscribes to `SPX` minute candles plus the `SPXW` option chain
- loads real chain snapshots from `~/.tickrake/data/options/schwab`
- selects short put / short call legs near 10-delta and buys farther OTM wings
- opens one condor during the session and closes it later the same day

The runnable script is [examples/sampled_spxw_iron_condor_backtest.rb](../../examples/sampled_spxw_iron_condor_backtest.rb).

## Required Data Layout

This example expects:

- `SPX_1min.csv` under a history provider folder such as `history/ibkr-paper`
- `SPXW_exp*.csv` files under `options/schwab`

On this machine the script uses the sample chains in:

```text
~/.tickrake/data/options/schwab
```

## Running The Example

From the repository root:

```bash
ruby examples/sampled_spxw_iron_condor_backtest.rb
```

Optional override:

```bash
export QUANT_RB_DATA_PATH=/path/to/data/root
```

## Strategy Source

The shared strategy implementation lives at [doc/reference/spxw_iron_condor_examples.rb](../reference/spxw_iron_condor_examples.rb).

This script uses the `SampledSpxwIronCondorExample` class in that file.
