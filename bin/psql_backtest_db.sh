#!/bin/bash

# Connect to Backtest Database Script
# This script opens a psql prompt connected to the local backtest database

set -e  # Exit on any error

DB_DATA_DIR='/Volumes/ext_docs/options_trader/db'
DATABASE_NAME='options_trader_db'
DATABASE_USER='options_trader'
DATABASE_HOST='localhost'
DATABASE_PORT=6543

echo "Connecting to backtest database..."

if [ ! -d "/Volumes/ext_docs/options_trader" ]; then
    echo "Error: External volume path /Volumes/ext_docs/options_trader does not exist"
    echo "Please ensure the external drive is mounted"
    exit 1
fi

if [ ! -f "$DB_DATA_DIR/postgresql.conf" ]; then
    echo "Error: Database cluster not found at $DB_DATA_DIR"
    echo "Please run bin/create_backtest_db.sh first to create the database"
    exit 1
fi

if ! pg_ctl -D "$DB_DATA_DIR" status > /dev/null 2>&1; then
    echo "PostgreSQL is not running. Starting it now..."
    ./bin/start_backtest_db.sh
    sleep 2
fi

echo "Opening psql connection to $DATABASE_NAME as $DATABASE_USER..."
echo "Database: $DATABASE_NAME"
echo "Host: $DATABASE_HOST"
echo "Port: $DATABASE_PORT"
echo "User: $DATABASE_USER"

# Connect to the database
psql -h "$DATABASE_HOST" -p "$DATABASE_PORT" -d "$DATABASE_NAME" -U "$DATABASE_USER"