# Installing SQLite with ActiveRecord

Follow these steps to set up the SQLite database with ActiveRecord:

## 1. Install Dependencies

```bash
bundle install
```

This will install the SQLite3 gem that was added to the Gemfile.

## 2. Initialize the Database

```bash
bundle exec rake persistence:test
```

This will:
- Create the SQLite database file in the db/ directory
- Run migrations to create the necessary tables
- Test the database connection

## 3. Test with an Example

```bash
bundle exec rake persistence:example
```

This will run an example that demonstrates how to use the persistence layer with your business logic.

## 4. Database Management Commands

- `bundle exec rake db:init` - Initialize the database
- `bundle exec rake db:migrate` - Run migrations
- `bundle exec rake db:reset` - Reset the database (drop, init, migrate)
- `bundle exec rake db:schema` - View the current schema

## 5. Implementation Details

- Database configuration: `config/database.yml`
- Database connection: `config/environment.rb`
- Migration script: `db/migrations/create_tables.rb`
- Models: `models/` (namespaced under `Persistence::`)
- Repository pattern: `services/repository.rb`

## 6. Namespacing Strategy

To avoid conflicts between business logic and persistence classes, we use:
- `Persistence::Trade` - ActiveRecord model for database operations
- `Services::Trades::Trade` - Business logic class

## 7. Using the Repository Pattern

The Repository class bridges between business logic and persistence:

```ruby
# Using business logic
trade = Services::Trades::PutSpread.new(...)

# Persisting to database
db_trade = Repository.save_trade(
  underlying: trade.underlying_symbol,
  strategy: "PUT_SPREAD",
  open_date: Date.today
)
```

See `PERSISTENCE.md` for more detailed documentation on using the persistence layer.