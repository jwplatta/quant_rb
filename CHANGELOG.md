# Changelog

All notable changes to `quant_rb` will be documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic Versioning.

## [0.1.0] - 2026-04-15

Initial release.

### Added

- event-driven `QuantRb::BacktestEngine` for local-data backtesting
- candle and options-chain data loading for tickrake-style CSV history
- explicit sampled and synthetic options-chain modes
- `SpySmaCrossover` and SPXW iron condor runnable examples
- reporting primitives: `TradeRecord`, `Metrics`, `BacktestResult`
- backtest artifact persistence for summary/trade outputs
- shared logging utility with configurable log level

### Notes

- `0.1.0` is a **backtesting-focused** release
- paper trading and live trading adapters are not included yet
