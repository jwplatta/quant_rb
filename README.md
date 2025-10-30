# Options Trader

Automated options trading system for discovering, entering, monitoring, and exiting options strategies using the Charles Schwab API.

## Purpose

This system automates the complete lifecycle of options trading:
- **Discovery**: Searches option chains for strategies meeting Greek and credit criteria
- **Execution**: Places orders via Schwab API with paper/live trading modes
- **Monitoring**: Tracks P&L and risk metrics against configurable thresholds
- **Exit**: Automatically closes positions at profit targets or stop losses
- **Analysis**: Backtests strategies using historical data and predicted Greeks

## Quick Start

```ruby
require 'options_trader'

bot = OptionsTrader.create_bot do
  set_name 'SPX Weekly Iron Condor Bot'
  set_mode :paper
  set_account_name 'YOUR_ACCOUNT'

  use_strategy 'ironcondor' do
    set_underlying_symbol '$SPX'
    set_days_to_expiration 1
    set_min_credit 1.00
    set_max_delta 0.15
  end

  exit_when do
    profit_target_threshold 0.7  # Exit at 70% profit
    max_loss_threshold 2.5       # Stop at 2.5x credit loss
  end
end

bot.start
```

## Setup

```bash
bundle install
rake db:init
rake db:migrate
```

Configure environment variables in `.env`:
```bash
SCHWAB_APP_KEY=your_app_key
SCHWAB_SECRET=your_secret
YOUR_ACCOUNT=your_account_number
```

## Key Components

### Trading Bot (`lib/options_trader/automation/bot.rb`)
- Main loop managing trade lifecycle
- Persists current trade state to disk
- Coordinates strategy finders and order managers

### Trade Lifecycle (`lib/options_trader/trades/trade.rb`)
State machine tracking: `TRADE_FOUND` → `OPEN_ORDER_SENT` → `TRADE_ENTERED` → `TRADE_EXITED`

Key helpers:
- **OrderManager**: Handles order placement and status checks
- **TradeProgress**: Monitors P&L vs profit/loss thresholds
- **RiskMonitor**: Tracks delta risk levels (green/yellow/red)
- **TradeJournal**: Persists trade events

### Strategies (`lib/options_trader/strategies/`)
- **IronCondor**: Sell put spread + sell call spread
- **CallSpread/PutSpread**: Vertical spreads
- **CallOption/PutOption**: Single legs

All strategies inherit from `StrategyBase` and implement:
- `type()`: Strategy identifier
- `to_h()`/`from_h()`: Serialization
- `delta()`: Greeks calculation

### Strategy Discovery (`lib/options_trader/search/`)
Finds optimal strategies from live option chains:

```ruby
StrategyFinderFactory.find(
  strategy_type: 'ironcondor',
  underlying_symbol: '$SPX',
  expiration_date: Date.today + 1,
  short_delta: 0.05,
  max_spread: 10.0,
  min_credit: 100.0
)
```

### Schwab Integration (`lib/options_trader/schwab/`)
Wrapper around `schwab_rb` gem:
- `quote(symbol)`, `option_chain(symbol)`
- `build_and_place_order()`, `build_and_preview_order()`
- `get_account_orders()`, `cancel_order()`
- Multiple account support via `Accounts` class

### Greek Calculations (`lib/options_trader/indicators/`)
- **BlackScholes**: Classic pricing model
- **CoxRossRubinstein**: Binomial model
- **ImpliedVolatility**: IV calculation
- **HistoricalVolatility**: Historical vol estimation
- **VixVolatility**: VIX-based vol

### Backtesting (`lib/options_trader/backtest/`)
Historical strategy simulation using:
- **OptionsStrategy**: Strategy backtesting
- **HistoricalSnapshot**: Point-in-time data reconstruction
- **DeltaEnricher**: ML-predicted Greeks via Greek Forge service
- Bitemporal option chain history (valid_time + transaction_time)

### Data Providers
- **Schwab** (`lib/options_trader/data_providers/schwab/`): Live market data
- **Polygon** (`lib/options_trader/data_providers/polygon/`): Historical data import
- **Greek Forge** (`lib/options_trader/predictors/greek_forge.rb`): ML Greek predictions

## Architecture Design Choices

### State Machine Pattern
Trade lifecycle uses explicit state transitions rather than implicit flags, ensuring predictable behavior and easy debugging.

### Factory Pattern
`StrategyFinderFactory` enables runtime strategy selection without conditional logic in calling code.

### Data Objects
Immutable value objects (`Option`, `OptionsChain`, `Quote`) provide type safety and consistent serialization via `to_h()`/`from_h()`.

### Service Composition
Services like `DeltaEnricher` and `HistoricalSnapshot` are composable units that can be tested independently and combined in backtesting pipelines.

### DSL Builders
Ruby DSL provides readable configuration while maintaining type safety and validation in builder classes.

### Mixins for Cross-Cutting Concerns
`Loggable`, `Quoteable`, and `Schwab` modules provide shared functionality without inheritance coupling.

## Testing

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/trades/trade_spec.rb

# Run test at specific line
bundle exec rspec spec/trades/trade_spec.rb:42

# Run focused tests
bundle exec rspec --focus
```

Current test status: Core components fully tested (Schwab integration, strategies, finders, data objects). Portfolio refactoring pending.

## What Still Needs to Be Done

### High Priority
- [ ] Strategy adjustment DSL implementation (rollup/rollout on delta breaches)
- [ ] Implement backtesting

### Medium Priority
- [ ] Alert system (webhook/email notifications on risk events)
- [ ] Support additional exchanges beyond Schwab

### Low Priority
- [ ] Web UI for bot monitoring and configuration
- [ ] Additional strategy types (straddles, strangles, butterflies)
- [ ] Position sizing based on portfolio allocation

## Project Structure

```
lib/options_trader/
├── automation/         # Bot framework
├── backtest/          # Backtesting engine
├── charts/            # Visualization
├── data_objects/      # Immutable value objects
├── data_providers/    # Schwab, Polygon integrations
├── indicators/        # Greeks calculations
├── models/            # ActiveRecord models
├── predictors/        # ML integrations (Greek Forge)
├── search/            # Strategy discovery
├── services/          # Business logic orchestration
├── strategies/        # Strategy implementations
├── trades/            # Trade lifecycle management
└── workers/           # Background jobs

spec/                  # RSpec tests mirroring lib/
scripts/               # Utility and example scripts
db/migrate/            # Database migrations
doc/                   # Architecture documentation
```

## Resources

- [Schwab Developer Portal](https://developer.schwab.com/)
- [schwab_rb gem](https://github.com/zoharsacks/schwab_rb)

## License

MIT License - see [LICENSE](LICENSE) file for details.

Copyright (c) 2025 Joseph Platta
