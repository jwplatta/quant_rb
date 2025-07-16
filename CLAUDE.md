# OptionsTrader Project Guide

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

## Code Style Guidelines
- Ruby version: 3.2.2
- Zero-monkey patching mode in RSpec tests
- ActiveRecord for database models and migrations
- Use mixins for shared functionality (e.g., logger.rb, orderable.rb)
- Naming: snake_case for methods/variables, CamelCase for classes
- Organization: Group related classes in directories by domain
- Error handling: Use exceptions with meaningful messages
- Prefer explicit requires rather than auto-loading
- Keep classes small and focused on a single responsibility
- Use validations in ActiveRecord models

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