#!/bin/bash

# Create Local Backtest Database Script
# This script creates a PostgreSQL database for backtesting with the specified configuration

set -e  # Exit on any error

# Database configuration from development settings
DATABASE_NAME_DEV='options_trader_db'
DATABASE_USER_DEV='options_trader'
DATABASE_PASSWORD_DEV='options_trader'
DATABASE_PORT_DEV=6543
DATABASE_HOST_DEV='localhost'
DB_DATA_DIR='/Volumes/ext_docs/options_trader/db'

echo "Creating local backtest PostgreSQL database..."

# Check if external volume path exists
if [ ! -d "/Volumes/ext_docs/options_trader" ]; then
    echo "Error: External volume path /Volumes/ext_docs/options_trader does not exist"
    echo "Please ensure the external drive is mounted"
    exit 1
fi

# Create data directory if it doesn't exist
mkdir -p "$DB_DATA_DIR"

# Initialize the database cluster if it doesn't exist
if [ ! -f "$DB_DATA_DIR/postgresql.conf" ]; then
    echo "Initializing PostgreSQL database cluster at $DB_DATA_DIR..."
    initdb -D "$DB_DATA_DIR" --auth-local=trust --auth-host=md5
    
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

# Create user if it doesn't exist
echo "Creating database user '$DATABASE_USER_DEV'..."
psql -h "$DATABASE_HOST_DEV" -p "$DATABASE_PORT_DEV" -d postgres -c "
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_user WHERE usename = '$DATABASE_USER_DEV') THEN
        CREATE USER $DATABASE_USER_DEV WITH PASSWORD '$DATABASE_PASSWORD_DEV';
    END IF;
END
\$\$;" || echo "User creation may have failed, continuing..."

# Create database if it doesn't exist
echo "Creating database '$DATABASE_NAME_DEV'..."
psql -h "$DATABASE_HOST_DEV" -p "$DATABASE_PORT_DEV" -d postgres -c "
SELECT 'CREATE DATABASE $DATABASE_NAME_DEV OWNER $DATABASE_USER_DEV'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$DATABASE_NAME_DEV')\gexec" || echo "Database creation may have failed, continuing..."

# Grant privileges
echo "Granting privileges to user '$DATABASE_USER_DEV'..."
psql -h "$DATABASE_HOST_DEV" -p "$DATABASE_PORT_DEV" -d "$DATABASE_NAME_DEV" -c "
GRANT ALL PRIVILEGES ON DATABASE $DATABASE_NAME_DEV TO $DATABASE_USER_DEV;
GRANT ALL PRIVILEGES ON SCHEMA public TO $DATABASE_USER_DEV;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $DATABASE_USER_DEV;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $DATABASE_USER_DEV;" || echo "Privilege granting may have failed, continuing..."

echo ""
echo "Database setup complete!"
echo "Database Name: $DATABASE_NAME_DEV"
echo "User: $DATABASE_USER_DEV"
echo "Host: $DATABASE_HOST_DEV"
echo "Port: $DATABASE_PORT_DEV"
echo "Data Directory: $DB_DATA_DIR"
echo ""
echo "Next steps:"
echo "1. Set environment variables:"
echo "   export DATABASE_NAME_DEV='$DATABASE_NAME_DEV'"
echo "   export DATABASE_USER_DEV='$DATABASE_USER_DEV'"
echo "   export DATABASE_PASSWORD_DEV='$DATABASE_PASSWORD_DEV'"
echo "   export DATABASE_PORT_DEV=$DATABASE_PORT_DEV"
echo "   export DATABASE_HOST_DEV='$DATABASE_HOST_DEV'"
echo ""
echo "2. Run migrations:"
echo "   rake db:migrate"
echo ""
echo "3. Use bin/start_backtest_db.sh to start the database in the future"