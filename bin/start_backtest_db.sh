#!/bin/bash

# Start Local Backtest Database Script
# This script starts the PostgreSQL database for backtesting

set -e  # Exit on any error

DB_DATA_DIR='/Volumes/ext_docs/options_trader/db'

echo "Starting local backtest PostgreSQL database..."

# Check if external volume path exists
if [ ! -d "/Volumes/ext_docs/options_trader" ]; then
    echo "Error: External volume path /Volumes/ext_docs/options_trader does not exist"
    echo "Please ensure the external drive is mounted"
    exit 1
fi

# Check if database cluster exists
if [ ! -f "$DB_DATA_DIR/postgresql.conf" ]; then
    echo "Error: Database cluster not found at $DB_DATA_DIR"
    echo "Please run bin/create_backtest_db.sh first to create the database"
    exit 1
fi

# Check if PostgreSQL is already running
if pg_ctl -D "$DB_DATA_DIR" status > /dev/null 2>&1; then
    echo "PostgreSQL is already running"
    exit 0
fi

# Start PostgreSQL server
echo "Starting PostgreSQL server with data directory: $DB_DATA_DIR"
pg_ctl -D "$DB_DATA_DIR" -l "$DB_DATA_DIR/log" start

# Wait for server to start
sleep 3

# Verify the server is running
if pg_ctl -D "$DB_DATA_DIR" status > /dev/null 2>&1; then
    echo "PostgreSQL server started successfully"
    echo "Log file: $DB_DATA_DIR/log"
    echo ""
    echo "Environment variables for connection:"
    echo "export DATABASE_NAME_DEV='options_trader_db'"
    echo "export DATABASE_USER_DEV='options_trader'"
    echo "export DATABASE_PASSWORD_DEV='options_trader'"
    echo "export DATABASE_PORT_DEV=6543"
    echo "export DATABASE_HOST_DEV='localhost'"
else
    echo "Failed to start PostgreSQL server"
    echo "Check the log file: $DB_DATA_DIR/log"
    exit 1
fi