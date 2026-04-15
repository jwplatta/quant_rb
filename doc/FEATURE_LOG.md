# Feature Log

This document tracks near-term and medium-term features that are good candidates for future `quant_rb` development.

It is intentionally lighter-weight than `doc/REWRITE_PLAN.md`. Use it for follow-up ideas, product gaps, tooling improvements, and quality-of-life features that should stay visible as the gem evolves.

## Backtest Tooling

- Add an MCP server interface so Claude/Codex-style agents can launch and inspect `quant_rb` backtests programmatically.
- Add a progress bar or similar progress reporting for long-running backtests.

## Execution Realism

- Add configurable transaction costs for backtests.
- Add configurable slippage for backtests.
- Improve synthetic options-chain execution realism with a configurable bid/ask spread model and a reasonable fill/slippage model for multi-leg options trades.

