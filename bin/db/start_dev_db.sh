#!/bin/bash

# Start Local Backtest Database Script
# This script starts the PostgreSQL database for backtesting

set -e

DB_DATA_DIR='/Users/jplatta/.options_trader/db'

echo "Starting local backtest PostgreSQL database..."

if [ ! -d "$DB_DATA_DIR" ]; then
    echo "Error: External volume path $DB_DATA_DIR does not exist"
    echo "Please ensure the external drive is mounted"
    exit 1
fi

if [ ! -f "$DB_DATA_DIR/postgresql.conf" ]; then
    echo "Error: Database cluster not found at $DB_DATA_DIR"
    echo "Please run bin/create_backtest_db.sh first to create the database"
    exit 1
fi

if pg_ctl -D "$DB_DATA_DIR" status > /dev/null 2>&1; then
    echo "PostgreSQL is already running"
    exit 0
fi

echo "Starting PostgreSQL server with data directory: $DB_DATA_DIR"
pg_ctl -D "$DB_DATA_DIR" -l "$DB_DATA_DIR/log" start

sleep 3

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