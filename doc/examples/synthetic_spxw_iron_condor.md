# Synthetic SPXW Iron Condor

## Overview

This example runs a simple `SPXW` iron condor strategy against **synthetic** options chains generated from minute history.

The strategy:

- subscribes to `SPX` minute candles plus the `SPXW` option chain
- explicitly injects a `QuantRb::Data::Index::SyntheticOptionsChainIndex`
- lets `QuantRb::Data::Synthetic::SyntheticChainBuilder` generate the chain on demand
- selects short put / short call legs near 10-delta and buys farther OTM wings
- opens one condor during the session and closes it later the same day

The runnable script is [examples/synthetic_spxw_iron_condor_backtest.rb](../../examples/synthetic_spxw_iron_condor_backtest.rb).

## Required Data Layout

This example needs minute history for:

- `SPX_1min.csv`
- `VIX_1min.csv`
- `VIX9D_1min.csv`
- optionally `VIX1D_1min.csv`

By default the script searches these history subpaths in order:

- `history/ibkr-paper`
- `history/ibkr`
- `history/schwab`

The script does **not** require real option chain files.

## Running The Example

From the repository root:

```bash
ruby examples/synthetic_spxw_iron_condor_backtest.rb
```

Optional overrides:

```bash
export QUANT_RB_DATA_PATH=/path/to/data/root
```

## Strategy Source

The strategy implementation lives at [doc/reference/spxw_iron_condor_examples.rb](../reference/spxw_iron_condor_examples.rb).

That file contains the shared iron-condor selection logic plus the `SyntheticSpxwIronCondorExample` class used by this script.
