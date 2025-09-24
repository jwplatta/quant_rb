<!-- Copilot instructions for the Options Trader repo -->

# Options Trader — Copilot Instructions

These concise instructions help AI coding assistants be productive in this repository. Focus on discoverable, actionable patterns and examples rather than generic advice.

1. Quick setup and common commands
   - Install deps: `bundle install`
   - DB init/migrate/reset: `rake db:init`, `rake db:migrate`, `rake db:reset`
   - Run tests: `bundle exec rspec` (or a specific spec: `bundle exec rspec spec/path/to_spec.rb`)
   - Refresh Schwab token (interactive): `bundle exec exe/schwab_token_refresh`
   - Start MCP server (AI-facing): `bundle exec exe/options_trader_mcp` or `./start_mcp_server.sh`

2. Big-picture architecture (where to look)
   - Core domain: `lib/options_trader/` — key subfolders: `schwab/`, `search/`, `strategies/`, `trades/`, `automation/`, `mcp/`, `charts/`.
   - MCP tools for agent integration: `lib/options_trader/mcp/tools/*` (see `help.rb` for examples and API surface).
   - Example bot: `spx_1DTE_bot.rb` demonstrates the Bot DSL and run patterns.
   - CLI/entrypoints: `exe/` contains runnable binaries (e.g., `options_trader_mcp`, `schwab_token_refresh`).

3. Project-specific conventions and patterns
   - Ruby version: 3.2.2 (Gemfile).
   - Prefer explicit requires (see `config/environment.rb`).
   - Data objects: Schwab responses are wrapped as immutable DataObjects (look under `lib/options_trader/schwab` and `lib/options_trader/data_objects/*`). Use `to_h`/`from_h` for serialization.
   - Strategies implement `type`, `to_h`, `from_h`, `symbols`, and `legs`. See `lib/options_trader/strategies/*` for concrete examples.
   - Factory pattern: Use `Search::StrategyFinderFactory` and `Schwab::Orders::OrderFactory` to construct finders and orders rather than instantiating low-level classes directly (see `lib/options_trader/search` and `lib/options_trader/schwab/orders`).
   - Bot DSL: Bots are configured with `OptionsTrader.create_bot do ... end`. Example in `spx_1DTE_bot.rb` and documented in `lib/options_trader/mcp/tools/help.rb`.
   - State machine: Trades use clear states (e.g., `SEARCHING`, `ORDER_PENDING`, `POSITION_ACTIVE`). Inspect `lib/options_trader/trades/*` for transitions.

4. Tests and test patterns
   - Tests use RSpec, FactoryBot, and DB transactions with rollback in `spec/spec_helper.rb`.
   - Run a single example with `bundle exec rspec spec/path/to_spec.rb:LINE`.
   - Use `--only-failures` and `--next-failure` (RSpec persistence enabled).

5. Integration points & environment
   - Schwab API: uses `schwab_rb` gem; tokens stored in `schwab_token.json` by default. Environment variables live in `.env` (see `lib/options_trader/mcp/tools/help.rb` setup section for names).
   - Account mapping: account names are provided via environment variables like `TRADING_BROKERAGE_ACCOUNT`.
   - Persistence: ActiveRecord with SQLite by default (see `config/database.yml`).
   - Optional services: Sidekiq and clockwork are present for background jobs; check `lib/tasks` and `bin/` for usage patterns.

6. Examples to copy/adapt
   - Create a finder: `OptionsTrader::Search::IronCondorFinder.new.find_strategies(underlying_symbol: '$SPX', expiration_date: 'YYYY-MM-DD', min_credit: 100.0, max_delta: 0.15)` (see `lib/options_trader/mcp/tools/help.rb`).
   - Create an order via factory: `OptionsTrader::Schwab::Orders::OrderFactory.new.create_iron_condor_order(strategy: s, quantity: 1, price: 1.5, instruction: 'SELL_TO_OPEN')`.
   - Bot DSL sample: `spx_1DTE_bot.rb` — prefer copying structure when creating new bots.

7. Safety and non-goals
   - Do not commit real credentials or account numbers. The repository contains `schwab_token.json` for local testing; never push real tokens to remote.
   - Avoid changing API semantics of MCP tools without updating `lib/options_trader/mcp/tools/help.rb` and `exe/options_trader_mcp`.

8. When to ask the human
   - If a change touches live-trading logic (code paths guarded by `mode: :live`), ask for explicit confirmation before changing behavior.
   - If an integration change affects the Schwab token flow or account mapping, request env values and intended account mapping.

9. Where to update docs/examples
   - Update `lib/options_trader/mcp/tools/help.rb` for MCP-facing API changes and examples.
   - Update `CLAUDE.md` and `README.md` for broader user-facing onboarding changes.

If anything here is unclear or you'd like more examples (e.g., common refactor patterns, typical unit test mocks), tell me which area to expand and I'll iterate.
