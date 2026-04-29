# Repository Guidelines

## Project Focus
- Active development is centered on the `quant_rb` gem and the code under `lib/quant_rb/`.
- Treat the `bots/` directory and other legacy `options_trader` code as reference material only. It exists to help with migration and design comparison, and it is expected to be removed.
- When making implementation decisions, prefer `quant_rb` architecture, APIs, and tests over legacy bot patterns.

## Project Structure & Module Organization
- Core gem code lives in `lib/quant_rb/`.
- Key areas include:
  - `engine/` for the event-driven runtime, scheduling, portfolio, orders, and positions
  - `data/` for loaders, indexes, synthetic chain builders, and market-data abstractions
  - `data_objects/` for candles, options, quotes, and chains
  - `reality/` for fill, slippage, and fee models
  - `reporting/` for metrics, trade records, backtest outputs, and progress reporting
  - `brokers/` for broker adapters and backtest broker behavior
- Specs for the gem live under `spec/quant_rb/`; fixtures live under `spec/fixtures/quant_rb/`.
- Runnable examples live in `examples/`; supporting design and migration notes live in `doc/`.
- The `bots/` folder is legacy `options_trader` code. Do not extend it unless the task is explicitly about migration or reference extraction.

## Build, Test, and Development Commands
- `bundle install` - install Ruby dependencies.
- `bundle exec rspec` - run the full spec suite.
- `bundle exec rspec spec/quant_rb` - run the active `quant_rb` specs only.
- `bundle exec rubocop` - lint the codebase with project rules from `rubocop.yml`.
- `bundle exec rake build` - build the gem package.
- `ruby examples/spy_sma_crossover_backtest.rb` - run the equity example backtest.
- `ruby examples/sampled_spxw_iron_condor_backtest.rb` - run the sampled options-chain example.
- `ruby examples/synthetic_spxw_iron_condor_backtest.rb` - run the synthetic options-chain example.

## Coding Style & Naming Conventions
- Ruby 3.1+ with two-space indentation.
- File names use `snake_case.rb`; classes and modules use `CamelCase`; methods and variables use `snake_case`; constants use `SCREAMING_SNAKE_CASE`.
- Favor small, composable objects with explicit responsibilities and deterministic behavior.
- Keep the public gem API and strategy-facing interfaces clear and stable; add brief comments where contracts are not obvious.
- Avoid coupling new `quant_rb` code to legacy `bots/` implementations.

## Testing Guidelines
- Framework: RSpec.
- Place specs alongside the active gem structure, for example `lib/quant_rb/engine/backtest_engine.rb` maps to `spec/quant_rb/engine/backtest_engine_spec.rb`.
- Prefer deterministic fixtures and local test data over live API calls.
- Prioritize coverage for backtest execution, scheduling, portfolio/order behavior, data loading, synthetic chain generation, and reporting.
- Add regression coverage for edge cases such as missing bars, sparse option chains, fill-model assumptions, and output persistence.
- Use `bundle exec rspec --format documentation` locally when debugging targeted failures.

## Legacy Code Guidance
- `bots/` and related legacy files are not the product surface. They are historical reference material during the `quant_rb` transition.
- It is acceptable to inspect legacy code for behavior parity, naming ideas, or migration context.
- New features, tests, and refactors should land in `lib/quant_rb/`, `spec/quant_rb/`, `examples/`, or relevant docs unless the task explicitly says otherwise.
- If a change touches both `quant_rb` and legacy code, keep the active gem implementation as the source of truth and minimize churn in legacy files.

## Commit & Pull Request Guidelines
- Keep diffs scoped to a single concern.
- Prefer short imperative commit messages. Conventional commits such as `feat:`, `fix:`, `refactor:`, `docs:`, and `test:` are preferred.
- Update `CHANGELOG.md` for user-visible gem changes. Skip changelog updates for internal-only refactors, tests, docs, or tooling.
- Bump `lib/quant_rb/version.rb` only when preparing a release, and pair it with the corresponding changelog entry.
- PRs should include a concise summary, relevant test commands, and notes about any behavior or data-layout changes.
- Keep secrets and local state out of git, including `.env` files, account credentials, tokens, and generated backtest artifacts.
