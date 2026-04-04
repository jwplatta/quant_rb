# Repository Guidelines

## Project Structure & Module Organization
- Core library lives in `lib/options_trader/` with key areas: `automation/` (bot loop), `search/` (strategy discovery), `strategies/` (iron condor, spreads), `trades/` (state machine + order handling), `data_providers/` (Schwab/Polygon), `predictors/` (Greek Forge), `backtest/`, `indicators/`, plus `services/` and `workers/`.
- Tests mirror the library under `spec/`; prefer placing fixtures in `spec/support/` or `data/` when heavier.
- Database migrations reside in `db/migrate/`; environment bootstraps via `config/environment`.
- Utility scripts live in `scripts/` and `bin/` (e.g., `bin/refresh_token.rb`, `bin/spx_9dte_sample_job.rb`); notebooks for exploration sit in `notebooks/`.

## Build, Test, and Development Commands
- `bundle install` – install Ruby dependencies.
- `bundle exec rake db:init db:migrate` – create and migrate the local database; add `db:reset` when you need a fresh schema.
- `bundle exec rspec` – run the full test suite; append a path or `:line` to scope (e.g., `bundle exec rspec spec/trades/trade_spec.rb:42`).
- `bundle exec rubocop` – lint/format with project rules from `rubocop.yml`.
- `ruby spx_1DTE_bot.rb` or `ruby bin/spx_9dte_sample_job.rb` – run example bots once your `.env` is populated.
- `docker-compose up` – start dependencies defined in `docker-compose.yml` (DB, services) when needed.

## Coding Style & Naming Conventions
- Ruby 3.x with two-space indentation; favor small, composable objects and explicit state transitions.
- File names `snake_case.rb`; classes/modules `CamelCase`; methods/vars `snake_case`; constants `SCREAMING_SNAKE`.
- Keep public APIs documented with brief comments; avoid broad mixins unless shared across multiple services.
- Run `bundle exec rubocop` before commits to stay aligned with enforced cops.

## Testing Guidelines
- Framework: RSpec. Place specs beside corresponding lib paths (e.g., `lib/options_trader/trades/` → `spec/trades/`).
- Name tests with `_spec.rb`; prefer focused examples (`it` blocks) and deterministic data builders over live API calls.
- Cover trading state machines, strategy finders, and Schwab integrations; include regression cases for edge states (timeouts, zero-liquidity chains).
- Use `bundle exec rspec --format documentation` locally when debugging; keep CI output concise by default.

## Commit & Pull Request Guidelines
- Commit messages follow the existing pattern: short imperative prefix with scope (`feature/high-risk-dates`, `fix/bot-loop-no-trade`, `refactor/state-machine-decision-tree`) plus PR reference when applicable.
- Squash noisy WIP commits locally; keep diffs scoped to a single concern.
- PRs should include: concise summary, testing notes (`bundle exec rspec`, `rubocop`), screenshots/log excerpts for behavioral changes, and links to related issues. Call out migration or config changes explicitly.
- Keep secrets out of git (`.env`, `schwab_token.json`, API keys); use `.env` for local credentials and never log sensitive fields.
