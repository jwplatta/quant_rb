# Plan: Add Postgres (Supabase) Database Configuration and Schema Management to options_trader

## 1. Add Database Configuration
- Extend `OptionsTrader::Configuration` to support DB settings:
  - Support both `DATABASE_URL` (single string) and individual params for flexibility
  - Use ENV vars: `DATABASE_URL` or `SUPABASE_DB_HOST`, `SUPABASE_DB_PORT`, `SUPABASE_DB_NAME`, `SUPABASE_DB_USER`, `SUPABASE_DB_PASSWORD`
  - Add connection pool configuration (`DB_POOL_SIZE`, default: 5)
- Add accessors and loading logic, following the existing ENV pattern.

## 2. Choose ORM & Migration Tool
- Use **ActiveRecord** for:
  - Schema definition and migrations
  - Model-based data access
- Add `activerecord` and `pg` gems to your gemspec/dependencies.
- Check current ActiveRecord version to match migration class version.

## 3. Setup ActiveRecord Integration
- Add an initializer (e.g., `lib/options_trader/db.rb`) to:
  - Establish connection using config/env with pool settings
  - Load models
- Example:
  ```ruby
  # filepath: lib/options_trader/db.rb
  require 'active_record'

  module OptionsTrader
    module DB
      def self.connect!
        config = build_config
        ActiveRecord::Base.establish_connection(config)
      end

      private

      def self.build_config
        if OptionsTrader.configuration.database_url
          { url: OptionsTrader.configuration.database_url }
        else
          {
            adapter: 'postgresql',
            host: OptionsTrader.configuration.db_host,
            port: OptionsTrader.configuration.db_port,
            database: OptionsTrader.configuration.db_name,
            username: OptionsTrader.configuration.db_user,
            password: OptionsTrader.configuration.db_password,
            pool: OptionsTrader.configuration.db_pool_size
          }
        end
      end
    end
  end
  ```

## 4. Manage Migrations
- Add a `db/migrate/` directory for migration files.
- Provide a Rake task or CLI command for running migrations.
- Use current ActiveRecord version for migration class.
- Example migration:
  ```ruby
  # filepath: db/migrate/20250802_create_trades.rb
  class CreateTrades < ActiveRecord::Migration[7.1]  # Match your AR version
    def change
      create_table :trades do |t|
        t.string :symbol, null: false
        t.decimal :price, precision: 10, scale: 2
        t.string :status
        t.timestamps
      end
      
      add_index :trades, :symbol
      add_index :trades, :status
    end
  end
  ```

## 5. Add Models
- Place models in `lib/options_trader/models/`.
- Example:
  ```ruby
  # filepath: lib/options_trader/models/trade.rb
  module OptionsTrader
    class Trade < ActiveRecord::Base
      validates :symbol, presence: true
      validates :price, presence: true, numericality: { greater_than: 0 }
    end
  end
  ```

## 6. Environment & Testing Configuration
- **Development/Production**: Use Supabase PostgreSQL
- **Test**: Use separate test database or in-memory PostgreSQL
- Add test database configuration in `spec_helper.rb`:
  ```ruby
  # In spec_helper.rb
  ENV['DATABASE_URL'] = 'postgresql://localhost/options_trader_test'
  # or use separate test env vars
  ```

## 7. Rake Tasks
- Add database-related Rake tasks:
  - `rake db:create` - Create database
  - `rake db:migrate` - Run migrations
  - `rake db:rollback` - Rollback last migration
  - `rake db:reset` - Drop, create, and migrate
  - `rake db:seed` - Load seed data

## 8. Update Documentation
- Document new ENV vars and configuration options.
- Add usage examples for DB access and migrations.
- Include Supabase connection setup instructions.

---

**Implementation Priority:**
1. Update configuration class with DB settings
2. Add database gems to gemspec
3. Create DB connection module
4. Add migration infrastructure and Rake tasks
5. Create initial models
6. Update test configuration

**Note:** No SQLite migration needed since the previous implementation was minimal.
