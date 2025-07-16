# Persistence Layer for OptionsTrader Trading App

This document outlines how to use the new SQLite-based persistence layer with ActiveRecord.

## Setup

1. Install dependencies:
   ```
   bundle install
   ```

2. Initialize the database:
   ```
   bundle exec rake persistence:test
   ```

3. Run the example to ensure it's working:
   ```
   bundle exec rake persistence:example
   ```

## Database Structure

The persistence layer consists of four main tables:

1. **trades** - Stores the main trade information
   - Has many trade_legs
   - Has many orders
   - Has many transactions through orders

2. **trade_legs** - Stores the individual legs of a trade
   - Belongs to a trade

3. **orders** - Stores orders placed for a trade
   - Belongs to a trade
   - Has many transactions

4. **transactions** - Stores transaction details
   - Belongs to an order

## Using the Repository Pattern

The `Repository` class provides a simple interface to interact with the database without directly coupling your business logic to ActiveRecord models.

```ruby
# Example: Creating a trade
trade = Repository.save_trade(
  underlying: "SPY",
  strategy: "PUT_SPREAD",
  open_date: Date.today
)

# Example: Adding a leg to a trade
leg = Repository.save_trade_leg(
  trade_id: trade.id,
  put_call: "PUT",
  symbol: "SPY230630P00430000",
  mark: 2.5,
  ask: 2.6,
  bid: 2.4,
  delta: -0.3,
  strike: 430.0,
  expiration_date: Date.new(2023, 6, 30),
  instruction: "SELL_TO_OPEN",
  quantity: 1
)

# Example: Finding trades
spy_trades = Repository.find_trades_by_underlying("SPY")
open_trades = Repository.find_open_trades
```

## Integration with Existing Business Logic

The persistence layer is designed to work alongside your existing business logic. Your service objects remain focused on business rules, and the repository handles persistence:

```ruby
# Create business logic object
put_spread = Services::Trades::PutSpread.new(...)

# Execute business logic
put_spread.calculate_risk_reward

# Use repository to persist the results
trade = Repository.save_trade(
  underlying: put_spread.underlying_symbol,
  strategy: "PUT_SPREAD",
  open_date: Date.today
)
```

## Namespace Organization

To avoid naming conflicts with your existing service objects:

- Database models are namespaced under `DB::` (e.g., `DB::Trade`)
- Service objects retain their original names (e.g., `Services::Trades::Trade`)
- The `Repository` class bridges between these layers

## Development and Testing

- Development environment: `RACK_ENV=development` (default)
- Test environment: `RACK_ENV=test`
- Production environment: `RACK_ENV=production`

## Database Operations

- Initialize database: `bundle exec rake persistence:test`
- Run example: `bundle exec rake persistence:example`
- View schema: `bundle exec rake db:schema`
- Reset database: `bundle exec rake db:reset`