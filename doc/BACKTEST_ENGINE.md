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

By default the engine creates a `QuantRb::Brokers::BacktestBroker`, but callers can inject their own broker:

```ruby
broker = QuantRb::Brokers::BacktestBroker.new(
  fill_model: QuantRb::Reality::BidAskFillModel.new,
  slippage_model: QuantRb::Reality::NullSlippageModel.new,
  transaction_fee_model: QuantRb::Reality::ZeroTransactionFeeModel.new
)

result = QuantRb::Engine::BacktestEngine.run(MyStrategy, broker: broker)
```

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

## Order And Fill Flow

Strategies submit orders through the injected broker. In backtests that is typically
`QuantRb::Brokers::BacktestBroker`.

The path is:

1. Strategy code calls an order helper such as `market_order`, `limit_order`, or `combo_limit_order`.
2. That helper constructs a `QuantRb::Engine::Order` and calls `broker.submit_order(order)`.
3. `BacktestBroker#submit_order` stores the order in `@pending_orders` and returns an `OrderTicket`.
4. On each engine time step, `BacktestEngine` calls `broker.process_pending_orders(slice, portfolio)`.
5. For each pending order the broker:
   - computes a raw fill price with the injected `fill_model`
   - adjusts that price with the injected `slippage_model`
   - checks whether the adjusted price satisfies the order's limit condition
   - computes fees and commissions with the injected `transaction_fee_model`
   - calls `portfolio.record_fill(...)`
   - removes the filled order from `@pending_orders`

The strategy submits orders, but fills happen later in the broker during the engine loop.

## Reality Model Design

Backtest execution realism is intentionally decomposed into single-responsibility models under
`QuantRb::Reality`.

### Fill Models

Fill models are responsible only for computing a raw execution price from the current `Slice`.
They do not apply slippage or fees.

Interface:

```ruby
class QuantRb::Reality::FillModel
  def simulate_fill(order, slice)
    raise NotImplementedError
  end
end
```

Current implementations:

- `QuantRb::Reality::OptimisticFillModel`
  Uses candle close for single-leg market orders and midpoint or mark for option combos.
- `QuantRb::Reality::BidAskFillModel`
  Extends the optimistic model and fills option sells at bid and buys at ask.

### Slippage Models

Slippage models are responsible only for transforming a raw fill price into a worse execution price.

Interface:

```ruby
class QuantRb::Reality::SlippageModel
  def adjust_price(base_price, order:, slice: nil)
    raise NotImplementedError
  end
end
```

Current implementations:

- `QuantRb::Reality::NullSlippageModel`
  Applies no slippage.
- `QuantRb::Reality::ConstantSlippageModel`
  Applies a constant adverse move based on order direction.

### Transaction Fee Models

Transaction fee models are responsible only for fees and commissions.

Interface:

```ruby
class QuantRb::Reality::TransactionFeeModel
  def estimate(order, fill_price: nil, slice: nil)
    raise NotImplementedError
  end
end
```

The return type is `QuantRb::Reality::CostBreakdown`, which exposes `fees`, `commissions`, and `total`.

Current implementations:

- `QuantRb::Reality::ZeroTransactionFeeModel`
  Applies no fees or commissions.
- `QuantRb::Reality::PerSpreadTransactionFeeModel`
  Applies fixed fees and commissions per spread unit.

## Dependency Injection

The engine depends only on the broker interface. The broker composes the execution realism behavior by
accepting injected models.

```ruby
broker = QuantRb::Brokers::BacktestBroker.new(
  fill_model: QuantRb::Reality::BidAskFillModel.new,
  slippage_model: QuantRb::Reality::ConstantSlippageModel.new(amount: 0.05),
  transaction_fee_model: QuantRb::Reality::PerSpreadTransactionFeeModel.new(
    option_fee_per_spread: 1.14,
    option_commission_per_spread: 1.30
  )
)
```

This keeps the responsibilities separate:

- fill model decides the raw price
- slippage model worsens that price
- fee model computes the transaction costs
- broker orchestrates the sequence and writes the result into the portfolio

Users can replace any one of these models without changing the engine or the broker.

## Portfolio Recording

Filled orders are written into `QuantRb::Engine::Portfolio`.

- `portfolio.record_fill(...)` opens or updates positions and debits transaction costs from cash.
- `portfolio.close_position(...)` closes an open position and records a `TradeRecord`.
- `QuantRb::Reporting::TradeRecord` tracks gross PnL separately from fees and commissions, and exposes
  net `pnl`.

One important design detail: `portfolio.close_position(...)` is a direct portfolio operation, not a broker
operation. If strategy code closes a position manually instead of submitting an exit order through the broker,
that code is responsible for passing any appropriate `transaction_costs:`.

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
- The engine itself does not know about fill, slippage, or fee models. Those concerns are broker-level
  execution realism concerns.
- Manual direct calls to `portfolio.close_position(...)` bypass broker-managed execution realism unless the
  caller explicitly supplies transaction costs.

## Files To Read

- `lib/quant_rb/engine/backtest_engine.rb`
- `lib/quant_rb/engine/strategy_base.rb`
- `lib/quant_rb/engine/slice.rb`
- `lib/quant_rb/data/index/options_chain_index.rb`
- `lib/quant_rb/brokers/backtest_broker.rb`
- `lib/quant_rb/reality/fill_model.rb`
- `lib/quant_rb/reality/slippage_model.rb`
- `lib/quant_rb/reality/transaction_fee_model.rb`
- `lib/quant_rb/engine/portfolio.rb`
- `lib/quant_rb/reporting/trade_record.rb`
