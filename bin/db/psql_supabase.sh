#!/bin/bash

# Connect to Supabase Database Script
# This script opens a psql prompt connected to the local Supabase database

set -e  # Exit on any error

# Load environment variables from .env if present
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

: "${DATABASE_NAME:?DATABASE_NAME is not set}"
: "${DATABASE_USER:?DATABASE_USER is not set}"
: "${DATABASE_PASSWORD:?DATABASE_PASSWORD is not set}"
: "${DATABASE_PORT:?DATABASE_PORT is not set}"
: "${DATABASE_HOST:?DATABASE_HOST is not set}"

echo "Connecting to Supabase database..."

echo "Opening psql connection to $DATABASE_NAME as $DATABASE_USER..."
echo "Database: $DATABASE_NAME"
echo "Host: $DATABASE_HOST"
echo "Port: $DATABASE_PORT"
echo "User: $DATABASE_USER"

PGPASSWORD="$DATABASE_PASSWORD" psql -h "$DATABASE_HOST" -p "$DATABASE_PORT" -d "$DATABASE_NAME" -U "$DATABASE_USER"