# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build/Lint/Test Commands
- `bundle install` - Install dependencies
- `rake db:init` - Initialize database
- `rake db:migrate` - Run database migrations
- `rake db:reset` - Reset database
- `bundle exec rspec` - Run all tests
- `bundle exec rspec spec/path/to/file_spec.rb` - Run specific test file
- `bundle exec rspec spec/path/to/file_spec.rb:42` - Run test at specific line
- `bundle exec rspec --focus` - Run tests tagged with :focus
- `bundle exec rspec --only-failures` - Run only failed tests

## Architecture Overview

This is a comprehensive options trading automation system built around these core components:

### Domain Structure
- **Schwab Integration** (`lib/options_trader/schwab/`): Wrapper around schwab_rb gem with data objects, order management, and API abstractions
- **Strategies** (`lib/options_trader/strategies/`): Options trading strategies (Iron Condor, Call/Put Spreads, individual options)
- **Search/Finders** (`lib/options_trader/search/`): Strategy discovery algorithms that find optimal option chains
- **Trades** (`lib/options_trader/trades/`): Trade lifecycle management with state machines and persistence
- **Automation** (`lib/options_trader/automation/`): Bot framework for automated trading with DSL configuration
- **Charts** (`lib/options_trader/charts/`): Visualization for trade performance and market data

### Key Patterns
- **Data Objects**: Immutable value objects for Schwab API responses (quotes, option chains, orders, etc.)
- **State Machine**: Trade objects use a comprehensive state machine with states like `TRADE_FOUND`, `OPEN_ORDER_SENT`, `TRADE_ENTERED`, `TRADE_EXITED`
- **Strategy Pattern**: Pluggable strategies inherit from `StrategyBase` and implement `type`, `to_h`, `from_h` methods
- **Factory Pattern**: `StrategyFinderFactory` and `OrderFactory` create appropriate instances based on strategy type
- **Mixin Pattern**: `Schwab` module provides API client methods, `Loggable` provides logging, `Quoteable` provides quote functionality

### Configuration & Environment
- Uses dotenv for environment variables (Schwab API keys, token paths)
- ActiveRecord with SQLite for persistence
- Paper trading vs live trading modes
- Account switching via `Accounts` class

### DSL Framework
The system implements a Ruby DSL for bot configuration:
```ruby
bot = OptionsTrader.create_bot do
  set_name 'SPX Weekly Iron Condor Bot'
  set_mode :paper
  use_strategy 'ironcondor' do
    set_underlying_symbol '$SPX'
    set_days_to_expiration 1
  end
  exit_when do
    profit_target_threshold 0.7
    max_loss_threshold 2.5
  end
end
```

## Code Style Guidelines
- Ruby version: 3.2.2
- Zero-monkey patching mode in RSpec tests
- ActiveRecord for database models and migrations
- Use mixins for shared functionality (e.g., logger.rb, Schwab module)
- Naming: snake_case for methods/variables, CamelCase for classes
- Organization: Group related classes in directories by domain
- Error handling: Use exceptions with meaningful messages
- Prefer explicit requires rather than auto-loading
- Keep classes small and focused on a single responsibility
- Use validations in ActiveRecord models
- Data objects should implement `to_h` and `from_h` for serialization

## Current Test Status
- Fixed DataObjects::QuoteFactory tests by handling nested JSON structure
- Fixed CallSpreadFinder/PutSpreadFinder tests by using the correct parameter name `opt_chain` instead of `option_chain`
- Added initial tests for the Schwab mixin, with most tests now working correctly
- Fixed JSON parsing issues in the Schwab#quote and Schwab#quotes methods
- Implemented comprehensive tests for DataObjects::Instrument, DataObjects::OptionDeliverable, and DataObjects::Asset classes
- Implemented and fixed Transaction and TransferItem tests
- Fixed transaction data transformation in the Schwab#transactions method
- Fixed the OrderPreview test by updating the fixture to match the Schwab API response format
- Fixed the get_order test by properly handling JSON parsing and string/integer comparison
- Fixed DataObjects::Transaction test to align with the Schwab API response format
- All Schwab mixin tests are now passing
- Remaining future work:
  - Portfolio.build: "unknown keyword: :positions" error (scheduled for future refactoring)
- Run specific tests with `bundle exec rspec spec/path/to/spec.rb`
- Skip specific tests with `bundle exec rspec --exclude-pattern "spec/path/to/spec.rb"`
- Focus on a specific test with `fit` or `fdescribe` in the spec file (requires :focus filter in spec_helper.rb)