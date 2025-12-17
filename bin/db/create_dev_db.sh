#!/bin/bash

# Create Local Backtest Database Script
# This script creates a PostgreSQL database for backtesting with the specified configuration

set -e  # Exit on any error

# Database configuration from development settings
DATABASE_NAME_DEV=${DATABASE_NAME_DEV:-'options_trader_db'}
DATABASE_USER_DEV=${DATABASE_USER_DEV:-'options_trader'}
DATABASE_PASSWORD_DEV=${DATABASE_PASSWORD_DEV:-'options_trader'}
DATABASE_PORT_DEV=${DATABASE_PORT_DEV:-6543}
DATABASE_HOST_DEV=${DATABASE_HOST_DEV:-'localhost'}
DB_DATA_DIR='/Users/jplatta/.options_trader/db'

echo "Creating local backtest PostgreSQL database..."

# Create data directory if it doesn't exist
mkdir -p "$DB_DATA_DIR"

# Initialize the database cluster if it doesn't exist
if [ ! -f "$DB_DATA_DIR/postgresql.conf" ]; then
    echo "Initializing PostgreSQL database cluster at $DB_DATA_DIR..."
    initdb -D "$DB_DATA_DIR" --auth-local=trust --auth-host=trust

    # Update postgresql.conf to use the correct port
    echo "port = $DATABASE_PORT_DEV" >> "$DB_DATA_DIR/postgresql.conf"
    echo "listen_addresses = '$DATABASE_HOST_DEV'" >> "$DB_DATA_DIR/postgresql.conf"
else
    echo "Database cluster already exists at $DB_DATA_DIR"
fi

# Start PostgreSQL server
echo "Starting PostgreSQL server..."
pg_ctl -D "$DB_DATA_DIR" -l "$DB_DATA_DIR/log" start

# Wait for server to start
sleep 3

# Initial database setup is now handled by rake tasks
echo "PostgreSQL cluster initialized. Use rake tasks for database and user management:"
echo "  RAILS_ENV=development RACK_ENV=development rake db:create"

echo ""
echo "PostgreSQL cluster setup complete!"
echo "Host: $DATABASE_HOST_DEV"
echo "Port: $DATABASE_PORT_DEV"
echo "Data Directory: $DB_DATA_DIR"
echo ""
echo "Next steps:"
echo "1. Create database and user with proper permissions:"
echo "   RAILS_ENV=development RACK_ENV=development rake db:create"
echo ""
echo "2. Run migrations:"
echo "   RAILS_ENV=development RACK_ENV=development rake db:migrate"
echo ""
echo "3. For future use:"
echo "   - Start database: bin/start_backtest_db.sh"
echo "   - Connect to DB: bin/psql_backtest_db.sh"
echo "   - Reset database: RAILS_ENV=development RACK_ENV=development rake db:reset"