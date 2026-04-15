# QuantRb Backtest Engine

## Overview

`QuantRb::Engine::BacktestEngine` runs an event-driven simulation over historical candle data.
At each candle timestamp it builds a `Slice`, updates subscribed securities, fires scheduled callbacks,
invokes the strategy's `on_data`, processes pending orders, and emits end-of-day hooks when the trading
date changes.

The public entry point is:

```ruby
result = QuantRb::Engine::BacktestEngine.run(MyStrategy)
```

That returns a `QuantRb::Reporting::BacktestResult` with the final portfolio value and completed trades.

## Lifecycle

1. The engine creates a temporary `Portfolio`, `Scheduler`, `Securities`, and broker.
2. It builds the strategy via `strategy_class.build_for_engine(...)` so the strategy can call
   `set_start_date`, `set_end_date`, `set_cash`, `add_equity`, and `add_index_option` during `initialize`.
3. After initialization, the engine replaces the temporary portfolio with one seeded from
   `strategy.initial_cash`.
4. It registers candle subscriptions in the securities registry.
5. It resolves the candle series and option-chain indexes, either from injected test doubles or from
   the configured data source.
6. It iterates over the primary candle series timestamp by timestamp.

## What Happens On Each Time Step

For each candle in the primary series:

1. `strategy.time` is set to the candle timestamp.
2. The engine loads bars for every subscribed candle symbol at that timestamp.
3. Those bars are pushed into the `Securities` registry so scheduled callbacks and strategy code can
   inspect current market state.
4. The scheduler fires any callbacks due at that time.
5. Option chains are loaded for every subscribed option root using `OptionsChainIndex#chains_at`.
   This uses per-expiry LOCF, but excludes expirations that are already before the slice date.
6. The engine builds a `Slice` containing:
   - `bars`: the candle data keyed by subscribed symbol
   - `option_chains`: hashes of expiry date to `OptionsChain`
   - `time`: the current timestamp
7. The engine calls `strategy.on_data(slice)`.
8. The broker processes any pending orders against the slice and records fills in the portfolio.
9. If the next candle falls on a different date, the engine calls `strategy.on_end_of_day` for each
   subscribed symbol.

After the loop finishes, the engine calls `strategy.on_end_of_algorithm`.

## Data Resolution

The engine supports two input paths:

- Default path: load candle history and option-chain indexes from `QuantRb::Data::DataSource`.
- Injected path: pass `candle_series:` and `options_chain_index:` into `.run` for tests or controlled
  simulations.

If a strategy has multiple subscriptions, injected data must be passed as a hash keyed by subscription
symbol. A single object is only accepted when there is exactly one subscription of that type.

## Important Constraints

- The engine requires at least one candle subscription. The first candle subscription becomes the primary
  timeline that drives the loop.
- Option chains are supplemental to the primary candle series. They are looked up at each candle timestamp;
  they do not define the simulation clock.
- Scheduled callbacks run before `on_data` for the same timestamp.
- End-of-day hooks are based on a date change in the primary candle series.

## Files To Read

- `lib/quant_rb/engine/backtest_engine.rb`
- `lib/quant_rb/engine/strategy_base.rb`
- `lib/quant_rb/engine/slice.rb`
- `lib/quant_rb/data/index/options_chain_index.rb`
- `lib/quant_rb/brokers/backtest_broker.rb`
