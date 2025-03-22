# Platypi Project Guide

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
- Some tests are failing with issues in:
  - DataObjects::QuoteFactory: "Unknown assetMainType" errors
  - Portfolio.build: "unknown keyword: :positions" error
  - CallSpreadFinder/PutSpreadFinder: "unknown keyword: :option_chain" errors
- Consider fixing these before proceeding with new development