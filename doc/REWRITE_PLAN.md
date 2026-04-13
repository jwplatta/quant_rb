# options_trader → quant_rb Refactor Plan

## Context

The `options_trader` gem is being refactored into `quant_rb`: a general-purpose QuantConnect-inspired event-driven backtesting engine for algorithmic strategies across all asset classes (stocks, ETFs, indexes, options, futures). The gem provides the engine, data loading, and broker abstractions. Strategy logic (Iron Condors, spreads, etc.) lives in consuming projects — not in the gem itself.

Immediate goal: backtesting short-vol options strategies using locally-stored CSV data (format produced by the `tickrake` scraper). The same strategy code must run unchanged for paper and live trading by swapping broker/data adapters.

Key constraints:
- No backwards compatibility with current `options_trader` code
- Leave `bots/` alone (reference only)
- No `strategies/` or `search/` modules in the gem — move existing code to `doc/reference/` as reference
- Data source is **configurable** (not hardcoded to tickrake paths); the gem just needs filename-parsing logic for the CSV format
- Support `schwab_rb` (v0.9.2) and `ib-api` as broker adapters
- Base strategy class: `QuantRb::Strategy` (not Algorithm)

---

## New Directory Structure (`lib/quant_rb/`)

```
engine/
  strategy_base.rb    # Base class users inherit from (QCAlgorithm equivalent)
                      # Exposed as QuantRb::Strategy
  backtest_engine.rb  # Drives the time loop
  live_engine.rb      # Stub: future paper/live trading
  scheduler.rb        # schedule.on(date_rules, time_rules, callback)
  date_rules.rb       # every_day, on(date), etc.
  time_rules.rb       # at(h,m), every(n_minutes), market_open/close
  slice.rb            # Data snapshot passed to on_data(slice)
  portfolio.rb        # Tracks cash, positions, P&L
  position.rb         # A single open position
  order.rb            # Order value object (legs, limit_price, direction)
  fill_model.rb       # Backtest fill simulation (bid/ask or mid)
  securities.rb       # securities[symbol].price registry

data/
  loaders/
    csv_options_chain.rb  # Parse single options chain CSV -> OptionsChain
    csv_candle.rb         # Parse candle CSV row -> Candle struct
  index/
    options_chain_index.rb  # In-memory index: sampled_at -> {expiry -> file_path}
                            # Filename parsing logic lives here
  series/
    candle_series.rb        # Sorted candle array with at(time) LOCF lookup
  data_source.rb            # Configurable root: QuantRb.configure { |c| c.data_path = "..." }
  synthetic/
    synthetic_chain_builder.rb  # Generates OptionsChain from candle data (SPX+VIX+VIX9D+VIX1D)
                                # Based on doc/generate_option_chain.rb prototype
                                # Used as fallback when no real samples exist for a date

data_objects/
  option.rb         # KEEP (value object with Greeks, to_h/from_h)
  options_chain.rb  # KEEP core
  quote.rb          # KEEP
  candle.rb         # NEW: datetime, open, high, low, close, volume

brokers/
  broker_adapter.rb    # Module interface: submit_order, cancel_order, get_quotes
  backtest_broker.rb   # Fill simulation using FillModel
  schwab_broker.rb     # Future: wraps schwab_rb
  ib_broker.rb         # Future: wraps ib-api

reporting/
  backtest_result.rb  # Aggregates trades, computes metrics
  trade_record.rb     # Immutable trade log entry
  metrics.rb          # Win rate, avg P&L, Sharpe, max drawdown
```

**Move to `doc/reference/` (not deleted, not part of gem load path):**
- `lib/options_trader/strategies/` → `doc/reference/strategies/`
- `lib/options_trader/search/` → `doc/reference/search/`

**Delete entirely:** `charts/`, `data_providers/`, `services/`, `models/`, `workers/`, `predictors/`, `synthetic_data/`, `backtest/`, `schwab/`, `indicators/`, `tasks/`, `trades/order_manager.rb`, `trades/trade.rb`, `trades/trade_builder.rb`, `trades/trade_journal.rb`, `trades/risk_monitor.rb`, `configuration.rb`.

---

## Key Class Designs

### QuantRb::Strategy (engine/strategy_base.rb)

```ruby
module QuantRb
  class Strategy
    attr_reader :time, :portfolio, :securities, :schedule, :broker

    # Called in user's initialize:
    def set_start_date(y, m, d); def set_end_date(y, m, d); def set_cash(amount)
    def add_index(symbol, resolution: :minute)               # -> symbol key
    def add_index_option(symbol, root, resolution:, &filter) # -> symbol key
    def add_equity(symbol, resolution: :minute)              # -> symbol key

    # Overridable event hooks (user overrides these):
    def initialize; end                    # Setup: dates, cash, schedule.on, etc.
    def on_data(slice); end                # Called every time step
    def on_end_of_day(symbol); end
    def on_end_of_algorithm; end

    # Order placement:
    def combo_limit_order(legs, quantity, limit_price)  # -> OrderTicket
    def market_order(symbol, quantity)                  # -> OrderTicket

    # Logging:
    def log(msg); def debug(msg)
  end
end
```

### QuantRb::BacktestEngine loop

```
Startup (once):
  1. Build OptionsChainIndex(root_path: QuantRb.config.data_path, symbol: "SPXW")
  2. Load CandleSeries for each subscribed candle symbol

Main loop (per minute candle):
  a. algo.time = candle.datetime
  b. scheduler.fire(current_time)                      # scheduled callbacks
  c. slice = SliceBuilder.build(algo, current_time)
       slice.bars[@spx]           = current Candle
       slice.option_chains[@spxw] = index.chains_at(current_time)  # LOCF
  d. algo.on_data(slice)
  e. broker.process_pending_orders(slice, portfolio)   # simulate fills
  f. if end_of_day: algo.on_end_of_day(each_symbol)

After loop:
  g. algo.on_end_of_algorithm
  h. Return BacktestResult
```

### Data Source Configuration

```ruby
QuantRb.configure do |config|
  config.data_path = "~/.tickrake/data"   # Root path for CSV data
  config.options_subpath = "options/schwab"
  config.history_subpath = "history/schwab"
end
```

The gem contains filename-parsing logic for the known CSV format:
- Options chains: `{SYMBOL}_exp{EXPIRY_DATE}_{SAMPLE_DATE}_{HH-MM-SS}.csv`
- Candles: `{SYMBOL}_{RESOLUTION}.csv`

### OptionsChainIndex

```ruby
index = QuantRb::Data::Index::OptionsChainIndex.new(
  root_path: QuantRb.config.options_data_path,
  symbol: "SPXW"
)
# Returns Hash of expiry -> OptionsChain, using LOCF for the given time
index.chains_at(Time.now)
```

Built once at engine startup. Binary search on sorted `sampled_at` keys for O(log n) LOCF lookup per time step. Lazy-loads CSV files only when requested.

### OptionsChainIndex — Real vs. Synthetic Fallback

For options backtesting, `OptionsChainIndex#chains_at` uses real samples when available and falls back to `SyntheticChainBuilder` when no real sample exists for a given date:

```
chains_at(target_time):
  1. Look up latest real sample <= target_time (LOCF from index)
  2. If found and within staleness threshold: return real chains
  3. Else: call SyntheticChainBuilder.build(target_time, candle_data)
            -> returns OptionsChain with Black-Scholes prices + delta anchors
```

`SyntheticChainBuilder` wraps the algorithm from `doc/generate_option_chain.rb`:
- Inputs: SPX + VIX + VIX9D + VIX1D minute candles
- Output: `OptionsChain` with interpolated vol surface and priced strikes

Callers (engine, strategies) receive the same `OptionsChain` interface regardless of source.

### BacktestBroker (fill simulation)

- Credit orders fill if `simulated_credit >= limit_price`
- Fill price: short legs at bid, long legs at ask (conservative default)
- Positions auto-expire on `on_end_of_day` when expiry == current date (settled at intrinsic)

---

## User-Facing Strategy DSL

Consumers of the gem write strategies in their own project:

```ruby
require "quant_rb"

# Simple equity example (for engine validation):
class SpySmaCrossover < QuantRb::Strategy
  def initialize
    set_start_date(2024, 1, 1)
    set_end_date(2024, 12, 31)
    set_cash(100_000)
    @spy = add_equity("SPY", resolution: :minute)
  end

  def on_data(slice)
    return unless slice.bars[@spy]
    fast_sma = securities[@spy].candles.last(10).map(&:close).sum / 10.0
    slow_sma = securities[@spy].candles.last(30).map(&:close).sum / 30.0
    if fast_sma > slow_sma && !portfolio.invested?
      market_order(@spy, 100)
    elsif fast_sma < slow_sma && portfolio.invested?
      market_order(@spy, -100)
    end
  end
end

# Options example (using doc/reference/ search/strategy code):
class Spxw7DteIronCondor < QuantRb::Strategy
  def initialize
    set_start_date(2024, 1, 1)
    set_end_date(2025, 12, 31)
    set_cash(50_000)
    @spx  = add_index("SPX", resolution: :minute)
    @spxw = add_index_option("SPX", "SPXW", resolution: :minute)
    @trade = nil
    schedule.on(date_rules.every_day(@spx), time_rules.at(15, 0), method(:check_entry))
  end

  def on_data(slice)
    return unless @trade && slice.option_chains[@spxw]
    monitor_position(slice.option_chains[@spxw])
  end

  def on_end_of_day(symbol)
    @trade = nil if @trade && time.to_date >= @trade[:expiry]
  end

  def on_end_of_algorithm
    log "Trades: #{portfolio.trade_history.size}, Final: $#{portfolio.total_value}"
  end
end

QuantRb.configure { |c| c.data_path = "~/.tickrake/data" }
result = QuantRb::BacktestEngine.run(SpySmaCrossover)
puts result.summary
```

Strategy/search logic (Iron Condors, vertical spreads, etc.) is implemented by the consumer using `doc/reference/` as a starting point.

---

## Parallel Development Structure

The modules are designed with minimal cross-dependencies so agents can work simultaneously:

| Agent | Owns | Depends on |
|-------|------|------------|
| **Data agent** | `data/`, `data_objects/` | Nothing else in the gem |
| **Engine agent** | `engine/` | `data_objects/` interfaces (Candle, OptionsChain, Option structs) |
| **Broker agent** | `brokers/` | `engine/order.rb` interface only |
| **Reporting agent** | `reporting/` | `engine/portfolio.rb`, `engine/position.rb` interfaces |

The contract between agents: agree on the `data_objects/` structs and the `engine/order.rb` shape upfront. Each agent can then work independently.

---

## Critical Reference Files

| File | Purpose |
|------|---------|
| `lib/options_trader/data_objects/option.rb` | Keep — clean value object, all Greeks |
| `lib/options_trader/data_objects/options_chain.rb` | Keep core |
| `bots/spx_1dte/iron_condor_finder.rb` | Reference for strategy authors |
| `bots/spx_1dte/trade_state_machine.rb` | Reference for monitoring logic |
| `doc/generate_option_chain.rb` | Reference for synthetic chain generation |
| `doc/spxw_7dte_recenter/` | Reference QC algorithm (Python) |

---

## Phased Implementation

### Phase 1: Gem Rename + Skeleton
Goal: Rename gem, establish new structure, move reference code to doc/.

1. Rename gem: `options_trader` → `quant_rb` (gemspec, module names, requires)
2. Move `lib/options_trader/strategies/` → `doc/reference/strategies/`
3. Move `lib/options_trader/search/` → `doc/reference/search/`
4. Delete all modules listed above
5. Create new `lib/quant_rb.rb` with empty module stubs and config struct
6. Keep `data_objects/option.rb`, `data_objects/options_chain.rb`, `data_objects/quote.rb` (re-namespace to `QuantRb::DataObjects`)

**Can run in parallel after this phase:** Data agent and Engine agent work simultaneously (Phases 2 & 3).

### Phase 2: Data Layer (parallelizable)
Goal: Load CSVs into `OptionsChain` and `Candle` objects via configurable data path.

1. `data_objects/candle.rb`
2. `data/loaders/csv_options_chain.rb` — parse `{SYMBOL}_exp*.csv` → `OptionsChain`
3. `data/loaders/csv_candle.rb` — parse candle CSV rows → `Candle`
4. `data/series/candle_series.rb` with LOCF `at(time)` lookup
5. `data/index/options_chain_index.rb` — scan configurable path, parse filenames, sorted index, LOCF `chains_at(time)`
6. `data/data_source.rb` — config-driven root path
7. RSpec: load real files from configured path, assert options with Greeks populated

**Contract for Engine agent:** `OptionsChainIndex#chains_at(Time) -> Hash{expiry => OptionsChain}` and `CandleSeries#at(Time) -> Candle`

### Phase 3: Engine Core (parallelizable with Phase 2)
Goal: Wirable engine with scheduler, portfolio, fill simulation.

1. `engine/scheduler.rb`, `date_rules.rb`, `time_rules.rb`
2. `engine/portfolio.rb`, `engine/position.rb`
3. `engine/order.rb`, `engine/fill_model.rb`
4. `brokers/broker_adapter.rb`, `brokers/backtest_broker.rb`
5. `engine/slice.rb`
6. `engine/strategy_base.rb` (exposes as `QuantRb::Strategy`)

**Contract for Data agent:** Slice is built using `OptionsChainIndex#chains_at` and `CandleSeries#at` interfaces above.

### Phase 4: Backtest Engine Loop
Goal: `QuantRb::BacktestEngine.run(StrategyClass)` executes and returns results.

1. `engine/backtest_engine.rb` — wires data + engine + broker
2. `reporting/trade_record.rb`, `reporting/backtest_result.rb`, `reporting/metrics.rb`
3. Update `lib/quant_rb.rb` to require all new files

### Phase 5a: First Working Strategy — SPY SMA Crossover (engine validation)
Goal: Validate the backtest engine end-to-end with a simple equity strategy before adding options complexity. SPY 1-min candles are available in tickrake data.

1. Write `SpySmaCrossover < QuantRb::Strategy`:
   - `add_equity("SPY", resolution: :minute)`
   - Fast SMA (10-period) and slow SMA (30-period) on close prices via `CandleSeries`
   - Enter long on fast > slow crossover; exit on fast < slow
   - Use `market_order` for fills
2. Run backtest over available SPY minute data
3. Verify: trade log entries, correct entry/exit times, portfolio cash changes, `BacktestResult` metrics

### Phase 5b: Options Backtesting — Real vs. Synthetic Chains
Goal: Add options chain data loading with fallback to synthetic generation when real samples are unavailable.

**Real chain path:** `OptionsChainIndex` loads actual samples from the configured options data path. When samples exist for the backtest date range, these are used directly (LOCF).

**Synthetic chain fallback:** When no real samples exist for a given date/time, generate a synthetic chain using the algorithm in `doc/generate_option_chain.rb`:
- Inputs: SPX + VIX + VIX9D + VIX1D minute candles (all available in tickrake history)
- Output: synthetic `OptionsChain` with Black-Scholes prices and delta anchors
- The `data/` layer exposes a unified interface — callers don't know whether they got real or synthetic data

Add a `SyntheticChainBuilder` to `data/synthetic/` that wraps `doc/generate_option_chain.rb` logic. Wire it into `OptionsChainIndex` as a fallback.

Then write `Spxw7DteIronCondor` strategy using `doc/reference/` and run a backtest over available data.

### Phase 6: Gemspec Cleanup
1. Remove: `activerecord`, `clockwork`, `sidekiq`, `sqlite3`, `aws-sdk-s3`, `rubyzip`
2. Keep: `dotenv`, stdlib `csv`
3. Final `lib/quant_rb.rb` require cleanup

### Phase 7: Live/Paper Stubs (Future)
1. `engine/live_engine.rb`
2. `brokers/schwab_broker.rb` (schwab_rb)
3. `brokers/ib_broker.rb` (ib-api)

---

## Agent Task Briefs

These briefs are written to be pasted directly into a Codex or other agent session. They assume Phase 1 (gem rename + skeleton) has already been committed before any of these agents start.

**Testing expectation for all agents:** Write RSpec unit tests alongside your code. Tests don't need to be comprehensive — just enough to confirm core functionality and prevent regressions when the work is merged. Small fixture files are preferred over real data files for unit tests. Integration tests that require local data files should be tagged `:integration`.

---

### Brief for Codex Agent 1 — Data Layer (Phase 2)

**Context:** We are rewriting the `options_trader` Ruby gem into `quant_rb` — a QuantConnect-inspired backtesting engine. Phase 1 (gem rename, new directory skeleton, shared data object stubs) has already been committed to the repo at `/Users/jplatta/repos/options_trader`. Your job is to implement the data loading layer.

**Your scope:** Everything under `lib/quant_rb/data/` and `lib/quant_rb/data_objects/candle.rb`. Do not touch `lib/quant_rb/engine/`, `lib/quant_rb/brokers/`, or `lib/quant_rb/reporting/`.

**What to build:**

1. `lib/quant_rb/data_objects/candle.rb` — simple value object: `datetime, open, high, low, close, volume`. Immutable (no setters).

2. `lib/quant_rb/data/loaders/csv_candle.rb` — parses rows from candle CSV files into `Candle` objects.
   - Candle CSV format (from `~/.tickrake/data/history/schwab/`): `datetime,open,high,low,close,volume`
   - datetime is ISO 8601: `2019-12-27T14:30:00Z`

3. `lib/quant_rb/data/loaders/csv_options_chain.rb` — parses a single options chain CSV file into a `QuantRb::DataObjects::OptionsChain` containing `QuantRb::DataObjects::Option` objects.
   - File naming pattern: `{SYMBOL}_exp{EXPIRY_DATE}_{SAMPLE_DATE}_{HH-MM-SS}.csv`
   - Example: `SPXW_exp2025-12-18_2025-12-18_13-50-58.csv`
   - Columns: `contract_type,symbol,description,strike,expiration_date,mark,bid,bid_size,ask,ask_size,last,last_size,open_interest,total_volume,delta,gamma,theta,vega,rho,volatility,theoretical_volatility,theoretical_option_value,intrinsic_value,extrinsic_value,underlying_price`
   - `contract_type` is `CALL` or `PUT`
   - All numeric columns should be parsed as Float (handle empty/nil gracefully)

4. `lib/quant_rb/data/series/candle_series.rb` — sorted collection of `Candle` objects for a single symbol.
   - `CandleLoader.load(symbol:, resolution:, data_path:)` — reads the CSV file for that symbol+resolution, returns a `CandleSeries`
   - `CandleSeries#at(time)` — returns the Candle with the largest `datetime <= time` (LOCF). Returns nil if none.
   - `CandleSeries#slice(start_time, end_time)` — returns array of Candles in range
   - `CandleSeries#last(n)` — returns last n Candles

5. `lib/quant_rb/data/index/options_chain_index.rb` — in-memory index of all chain files under a root path.
   - Constructor: `OptionsChainIndex.new(root_path:, symbol:)` — scans directory, parses filenames, builds sorted index
   - `#chains_at(target_time, expiry_filter: nil)` — returns `Hash { expiration_date (Date) => OptionsChain }` using LOCF (latest sampled_at <= target_time). Lazy-loads CSV files on first access.
   - Filename parsing: extract `expiry_date` and `sampled_at` from the filename pattern above.

6. `lib/quant_rb/data/data_source.rb` — reads config to resolve full paths.
   - `DataSource.options_path` → `File.join(QuantRb.config.data_path, QuantRb.config.options_subpath)`
   - `DataSource.history_path` → `File.join(QuantRb.config.data_path, QuantRb.config.history_subpath)`

**Existing code to reuse:** `lib/quant_rb/data_objects/option.rb` and `lib/quant_rb/data_objects/options_chain.rb` already exist (re-namespaced from the old gem). Build on them — don't rewrite them.

**Tests:** Write RSpec specs in `spec/quant_rb/data/`. Tests don't need to be comprehensive — just enough to confirm core functionality and catch regressions at merge time. Cover: CSV parsing produces the right object types and field values, `CandleSeries#at` returns correct LOCF result, `OptionsChainIndex#chains_at` returns the right chain for a given time. Use small fixture CSV files under `spec/fixtures/` for unit tests. Integration tests that load real files from `~/.tickrake/data/` should be tagged `:integration` so they can be skipped when data isn't present.

**Interface contract (for Engine agent):**
- `OptionsChainIndex#chains_at(Time) -> Hash { Date => QuantRb::DataObjects::OptionsChain }`
- `CandleSeries#at(Time) -> QuantRb::DataObjects::Candle | nil`
- `CandleSeries#last(n) -> Array<QuantRb::DataObjects::Candle>`

Do not implement synthetic chain generation — that comes later.

---

### Brief for Codex Agent 2 — Reporting + Backtest Engine Draft (Phase 4 prep)

**Context:** We are rewriting the `options_trader` Ruby gem into `quant_rb` — a QuantConnect-inspired backtesting engine. Phase 1 (gem rename, new directory skeleton, shared data object stubs) has already been committed to the repo at `/Users/jplatta/repos/options_trader`. The Engine Core (Phase 3) and Data Layer (Phase 2) are being built in parallel by other agents and are not yet available. Your job is to build the reporting layer and draft the backtest engine wiring — coding against the agreed interfaces.

**Your scope:** `lib/quant_rb/reporting/` and `lib/quant_rb/engine/backtest_engine.rb`. Do not touch `lib/quant_rb/data/`, `lib/quant_rb/brokers/`, or other engine files.

**What to build:**

1. `lib/quant_rb/reporting/trade_record.rb` — immutable value object logging a completed trade.
   - Fields: `id, strategy_class, symbol, direction (:long/:short/:credit/:debit), quantity, entry_price, exit_price, entry_time, exit_time, legs (Array of Hashes), notes`
   - `pnl` — computed: `(exit_price - entry_price) * quantity * 100` for options, `(exit_price - entry_price) * quantity` for equity
   - `duration_minutes` — computed from entry/exit times
   - `winner?` — true if pnl > 0

2. `lib/quant_rb/reporting/metrics.rb` — computes aggregate statistics from an array of `TradeRecord` objects.
   - `total_pnl` — sum of all trade pnl
   - `win_rate` — percentage of winning trades
   - `avg_pnl` — mean pnl per trade
   - `avg_winner`, `avg_loser`
   - `profit_factor` — gross profit / gross loss
   - `max_drawdown` — maximum peak-to-trough equity decline
   - `sharpe_ratio(risk_free_rate: 0.0)` — annualized Sharpe from daily P&L
   - Returns a plain struct/hash — no external dependencies

3. `lib/quant_rb/reporting/backtest_result.rb` — container returned by `BacktestEngine.run`.
   - Fields: `strategy_class, start_date, end_date, initial_cash, final_portfolio_value, trades (Array<TradeRecord>)`
   - `metrics` — returns `Metrics` computed from `trades`
   - `summary` — returns a formatted multi-line string suitable for `puts result.summary`

4. `lib/quant_rb/engine/backtest_engine.rb` — the main loop that wires everything together.
   - `BacktestEngine.run(strategy_class, broker: nil)` — class method, instantiates and runs
   - Wire up: instantiate strategy, inject portfolio/scheduler/securities/broker via `send`, call `strategy.initialize`
   - Main loop iterates over `CandleSeries` for the primary subscribed symbol (time steps)
   - On each step: fire scheduler, build slice, call `on_data`, call `broker.process_pending_orders`
   - End-of-day detection: fire `on_end_of_day` when the next candle is a different date
   - After loop: call `on_end_of_algorithm`, return `BacktestResult`
   - Use stub/interface calls for data objects — they will be replaced when Phase 2 merges:
     ```ruby
     # Stub — Phase 2 will provide the real implementation
     # candle_series = QuantRb::Data::Series::CandleLoader.load(symbol: ..., ...)
     # index = QuantRb::Data::Index::OptionsChainIndex.new(root_path: ..., symbol: ...)
     ```
   - The engine should work with whatever `CandleSeries` and `OptionsChainIndex` are injected (for testability)

**Interfaces to code against (provided by other agents, use these exact signatures):**

From Engine Core (Phase 3):
- `strategy.time`, `strategy.portfolio`, `strategy.schedule`, `strategy.securities`, `strategy.broker`
- `strategy.send(:set_time, current_time)`
- `strategy.subscribed_symbols -> Array<Symbol>`

From Data Layer (Phase 2):
- `candle_series.at(time) -> Candle | nil`
- `options_chain_index.chains_at(time) -> Hash { Date => OptionsChain }`

From Broker:
- `broker.process_pending_orders(slice, portfolio)`

**Tests:** Write RSpec specs in `spec/quant_rb/reporting/` and `spec/quant_rb/engine/backtest_engine_spec.rb`. Tests don't need to be comprehensive — just enough to confirm core functionality and catch regressions at merge time. Cover: `TradeRecord#pnl` and `#winner?` compute correctly, `Metrics` calculates win rate and total pnl from a small set of records, `BacktestResult#summary` returns a non-empty string, and the backtest engine runs a minimal strategy end-to-end with injected stub data (e.g. a strategy that counts `on_data` calls). Use stubs/doubles — no real CSV loading needed.

---

## Verification

- **Phase 2:** `QuantRb::Data::Index::OptionsChainIndex.new(...).chains_at(Time.now)` returns `OptionsChain` objects with populated Greeks
- **Phase 3:** `QuantRb::Engine::Scheduler` fires callbacks at correct simulated times
- **Phase 4:** `QuantRb::BacktestEngine.run(TestStrategy)` completes, returns `BacktestResult` with trades and final portfolio value
- **Phase 5a:** SPY SMA crossover backtest produces a trade log with correct entry/exit timestamps, non-zero P&L, and a valid `BacktestResult`
- **Phase 5b:** Options backtest uses real chain samples when present; falls back to synthetic chains (generated from SPX+VIX candles) when not. Iron Condor trades have entry credits in expected range (~$1.00–$2.50 for 7DTE SPXW)
