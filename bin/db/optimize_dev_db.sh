#!/bin/bash

# Optimize PostgreSQL for External Drive Storage
# ==============================================
# This script configures PostgreSQL settings to reduce index corruption
# when using an external drive for database storage.

set -e

DB_DATA_DIR='/Volumes/ext_docs/options_trader/db'
DB_PORT=6543

echo "Optimizing PostgreSQL configuration for external drive..."
echo "Data directory: $DB_DATA_DIR"
echo ""

# Check if PostgreSQL is running
if pg_ctl -D "$DB_DATA_DIR" status > /dev/null 2>&1; then
    echo "PostgreSQL is running. Stopping to update configuration..."
    pg_ctl -D "$DB_DATA_DIR" stop
    sleep 2
fi

# Backup postgresql.conf
cp "$DB_DATA_DIR/postgresql.conf" "$DB_DATA_DIR/postgresql.conf.backup"

# Add optimized settings for external drives to postgresql.conf
cat >> "$DB_DATA_DIR/postgresql.conf" <<EOF

# Optimizations for External Drive Storage
# -----------------------------------------
# These settings help prevent index corruption on external drives

# Reduce checkpoint frequency to minimize disk writes
checkpoint_timeout = 30min
checkpoint_completion_target = 0.9

# Increase WAL settings for better reliability
wal_buffers = 16MB
max_wal_size = 2GB
min_wal_size = 1GB

# Synchronous commits for data safety (slower but safer on external drives)
synchronous_commit = on
fsync = on
full_page_writes = on

# Memory settings
shared_buffers = 256MB
effective_cache_size = 1GB
work_mem = 16MB
maintenance_work_mem = 256MB

# Autovacuum settings to keep indexes healthy
autovacuum = on
autovacuum_max_workers = 2
autovacuum_naptime = 1min
EOF

echo "Configuration updated. Starting PostgreSQL..."
pg_ctl -D "$DB_DATA_DIR" -l "$DB_DATA_DIR/log" start
sleep 2

echo ""
echo "PostgreSQL optimized for external drive storage!"
echo ""
echo "Key optimizations applied:"
echo "  • Reduced checkpoint frequency (30 min)"
echo "  • Increased WAL buffers (16MB)"
echo "  • Enabled synchronous commits for safety"
echo "  • Configured autovacuum for index health"
echo ""
echo "You can now run imports with reduced risk of index corruption."