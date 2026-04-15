# quant_rb

`quant_rb` is a QuantConnect-inspired, event-driven backtesting engine for Ruby.

Version `0.1.0` is focused on **backtesting only**. It supports local-data strategy research for equities, indexes, and options. Paper trading and live trading adapters are planned, but they are not part of this first gem release.

## What It Includes

- event-driven backtest loop via `QuantRb::BacktestEngine`
- equity/index candle subscriptions
- sampled options-chain backtesting
- explicit synthetic options-chain generation for SPX-family workflows
- reporting, metrics, and trade history
- backtest artifact persistence to summary/trade files
- runnable example strategies

## Installation

Add the gem to your Gemfile:

```ruby
gem "quant_rb"
```

Or install it directly:

```bash
gem install quant_rb
```

## Current Scope

`quant_rb 0.1.0` is for:

- local backtesting
- strategy prototyping
- metrics and trade analysis
- file-based market data workflows

It is **not** yet for:

- paper trading
- live trading
- broker order routing
- production portfolio/account management

## Quick Start

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
    bar = slice.bars[@spy]
    return unless bar
  end
end

QuantRb.configure do |config|
  config.data_path = File.expand_path("~/.tickrake/data")
  config.history_subpath = "history/ibkr-paper"
  config.options_subpath = "options/schwab"
end

result = QuantRb::BacktestEngine.run(MyStrategy)
puts result.summary
```

## Data Layout

The engine expects a local data root, by default:

```text
~/.tickrake/data/
```

Typical layout:

```text
~/.tickrake/data/
  history/
    ibkr-paper/
      SPY_1min.csv
      SPX_1min.csv
      VIX_1min.csv
      VIX9D_1min.csv
  options/
    schwab/
      SPXW_exp2026-04-15_2026-04-14_13-30-14.csv
```

## Examples

Runnable examples live in [`examples/`](./examples):

- `ruby examples/spy_sma_crossover_backtest.rb`
- `ruby examples/sampled_spxw_iron_condor_backtest.rb`
- `ruby examples/synthetic_spxw_iron_condor_backtest.rb`

See also:

- [Getting Started](./doc/GETTING_STARTED.md)
- [Examples Index](./doc/examples/README.md)

## Reporting Outputs

Backtest results can be saved to disk:

```ruby
saved = result.save
puts saved[:summary_path]
puts saved[:trades_path]
```

Defaults:

- output directory: `~/.quant_rb/backtests`
- format: `csv`
- two files per run:
  - `unique_name_summary.csv`
  - `unique_name_trades.csv`

## Development

Install dependencies:

```bash
bundle install
```

Run tests:

```bash
bundle exec rspec spec/quant_rb
```

Build the gem:

```bash
bundle exec rake build
```

## Release Process

The repository includes a GitHub Actions workflow that builds the gem and creates a GitHub release when a version tag is pushed.

Expected tag format:

```bash
v0.1.0
```

The workflow validates that the tag matches `lib/quant_rb/version.rb`, builds the gem, and uploads the `.gem` file to the GitHub release.

## License

MIT. See [LICENSE](./LICENSE).
