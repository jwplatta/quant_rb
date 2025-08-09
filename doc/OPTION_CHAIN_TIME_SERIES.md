# Option Chain Time-Series

## Overview

For backtesting trading strategies, a simple time-series approach with 5-minute bucketed data is much more practical than a full bitemporal schema. This design downloads option chain data in 5-minute increments with only one valid record per contract per time segment.

## Schema Design

### Simple Time-Series Schema

```sql
CREATE TABLE option_chain_5min (
    -- Contract identification
    symbol VARCHAR(255),
    underlying_symbol VARCHAR(255),
    expiration_date DATE,
    strike DECIMAL(10,2),
    contract_type VARCHAR(4),

    -- Market data
    mark DECIMAL(10,2),
    bid DECIMAL(10,2),
    ask DECIMAL(10,2),
    last_price DECIMAL(10,2),
    underlying_price DECIMAL(10,2),

    -- Greeks
    delta DECIMAL(10,2),
    theta DECIMAL(10,2),
    vega DECIMAL(10,2),
    gamma DECIMAL(10,2),
    rho DECIMAL(10,2),

    -- Volume/Interest
    open_interest INTEGER,
    volume INTEGER,
    bid_size INTEGER,
    ask_size INTEGER,

    -- Option data
    intrinsic_value DECIMAL(10,2),
    extrinsic_value DECIMAL(10,2),
    time_value DECIMAL(10,2),
    volatility DECIMAL(10,2),

    -- 5-minute time bucket
    time_bucket TIMESTAMP NOT NULL,  -- e.g., '2025-08-01 10:00:00', '2025-08-01 10:05:00'

    PRIMARY KEY (symbol, time_bucket)
);

-- Indexes for efficient querying
CREATE INDEX idx_option_chain_5min_underlying ON option_chain_5min(underlying_symbol, time_bucket);
CREATE INDEX idx_option_chain_5min_expiration ON option_chain_5min(expiration_date, time_bucket);
CREATE INDEX idx_option_chain_5min_strike ON option_chain_5min(underlying_symbol, expiration_date, strike, contract_type, time_bucket);
```

## Data Collection Strategy

### Time Bucketing Approach

Data is collected and stored in 5-minute intervals aligned to:
- 09:30:00, 09:35:00, 09:40:00, etc.
- One record per contract per time bucket
- No overlapping or duplicate records for the same contract/time

### Sample Data Insert

```sql
-- Insert one record per contract per 5-minute interval
INSERT INTO option_chain_5min (
    symbol, underlying_symbol, expiration_date, strike, contract_type,
    mark, bid, ask, last_price, underlying_price,
    delta, theta, vega, gamma, rho,
    open_interest, volume, bid_size, ask_size,
    time_bucket
) VALUES (
    'SPX250810C06410', '$SPX', '2025-08-10', 6410.00, 'CALL',
    127.00, 125.80, 128.20, 126.50, 6538.92,
    0.65, -2.46, 8.92, 0.0045, 0.15,
    1250, 28, 45, 52,
    '2025-08-01 10:00:00'  -- Rounded to 5-min boundary
);

-- Next 5-minute bucket
INSERT INTO option_chain_5min (
    symbol, underlying_symbol, expiration_date, strike, contract_type,
    mark, bid, ask, last_price, underlying_price,
    delta, theta, vega, gamma, rho,
    open_interest, volume, bid_size, ask_size,
    time_bucket
) VALUES (
    'SPX250810C06410', '$SPX', '2025-08-10', 6410.00, 'CALL',
    128.50, 127.40, 129.60, 128.25, 6544.33,
    0.66, -2.44, 8.88, 0.0044, 0.16,
    1250, 41, 38, 47,
    '2025-08-01 10:05:00'
);
```

## Backtesting Queries

### Basic Data Retrieval

#### Get data for a specific time
```sql
SELECT mark, underlying_price, delta, bid, ask
FROM option_chain_5min
WHERE symbol = 'SPX250810C06410'
  AND time_bucket = '2025-08-01 10:00:00';
```

#### Get data for a time range (full trading day)
```sql
SELECT time_bucket, mark, underlying_price, delta, volume
FROM option_chain_5min
WHERE symbol = 'SPX250810C06410'
  AND time_bucket BETWEEN '2025-08-01 09:30:00' AND '2025-08-01 16:00:00'
ORDER BY time_bucket;
```

### Strategy Backtesting Queries

#### Price Movement Analysis
```sql
SELECT
    time_bucket,
    mark,
    underlying_price,
    mark - LAG(mark) OVER (ORDER BY time_bucket) as mark_change,
    underlying_price - LAG(underlying_price) OVER (ORDER BY time_bucket) as underlying_change,
    delta
FROM option_chain_5min
WHERE symbol = 'SPX250810C06410'
  AND time_bucket BETWEEN '2025-08-01 09:30:00' AND '2025-08-01 16:00:00'
ORDER BY time_bucket;
```

#### Multiple Contracts Analysis
```sql
-- Compare different strikes at the same time
SELECT
    time_bucket,
    strike,
    mark,
    delta,
    volume
FROM option_chain_5min
WHERE underlying_symbol = '$SPX'
  AND expiration_date = '2025-08-10'
  AND contract_type = 'CALL'
  AND strike IN (6400, 6410, 6420)
  AND time_bucket = '2025-08-01 14:00:00'
ORDER BY strike;
```

#### Trading Signal Generation
```sql
-- Example: Find contracts with significant mark movement
WITH price_changes AS (
    SELECT
        time_bucket,
        symbol,
        mark,
        LAG(mark, 1) OVER (PARTITION BY symbol ORDER BY time_bucket) as prev_mark,
        LAG(mark, 2) OVER (PARTITION BY symbol ORDER BY time_bucket) as prev_mark_2
    FROM option_chain_5min
    WHERE underlying_symbol = '$SPX'
      AND expiration_date = '2025-08-10'
      AND contract_type = 'CALL'
      AND time_bucket BETWEEN '2025-08-01 09:30:00' AND '2025-08-01 16:00:00'
)
SELECT
    time_bucket,
    symbol,
    mark,
    prev_mark,
    (mark - prev_mark) / prev_mark * 100 as pct_change_5min,
    (mark - prev_mark_2) / prev_mark_2 * 100 as pct_change_10min
FROM price_changes
WHERE prev_mark IS NOT NULL
  AND prev_mark_2 IS NOT NULL
  AND ABS((mark - prev_mark) / prev_mark) > 0.05  -- 5% threshold
ORDER BY time_bucket, symbol;
```

### Portfolio Analysis Queries

#### Position Tracking
```sql
-- Track multiple positions over time
SELECT
    time_bucket,
    SUM(CASE WHEN symbol = 'SPX250810C06400' THEN mark * 10 ELSE 0 END) as position_6400,
    SUM(CASE WHEN symbol = 'SPX250810C06410' THEN mark * (-5) ELSE 0 END) as position_6410,
    SUM(CASE WHEN symbol = 'SPX250810C06420' THEN mark * 10 ELSE 0 END) as position_6420
FROM option_chain_5min
WHERE symbol IN ('SPX250810C06400', 'SPX250810C06410', 'SPX250810C06420')
  AND time_bucket BETWEEN '2025-08-01 09:30:00' AND '2025-08-01 16:00:00'
GROUP BY time_bucket
ORDER BY time_bucket;
```

#### Risk Metrics
```sql
-- Calculate portfolio delta over time
SELECT
    time_bucket,
    SUM(delta * position_size) as portfolio_delta,
    SUM(gamma * position_size) as portfolio_gamma,
    SUM(theta * position_size) as portfolio_theta
FROM (
    SELECT
        time_bucket,
        delta,
        gamma,
        theta,
        CASE
            WHEN symbol = 'SPX250810C06400' THEN 10
            WHEN symbol = 'SPX250810C06410' THEN -5
            WHEN symbol = 'SPX250810C06420' THEN 10
        END as position_size
    FROM option_chain_5min
    WHERE symbol IN ('SPX250810C06400', 'SPX250810C06410', 'SPX250810C06420')
      AND time_bucket BETWEEN '2025-08-01 09:30:00' AND '2025-08-01 16:00:00'
) positioned_greeks
GROUP BY time_bucket
ORDER BY time_bucket;
```

## Benefits of This Approach

### Simplicity
- **One record per contract per time bucket**: No complex temporal logic
- **Direct time range filtering**: Simple `BETWEEN` clauses
- **No data overlap**: Clean, consistent intervals

### Performance
- **Fast queries**: Indexed time_bucket enables efficient range scans
- **Predictable data size**: Known intervals reduce storage vs. tick data
- **Sequential analysis**: Easy to process chronologically

### Backtesting Advantages
- **Consistent intervals**: No missing data gaps to handle
- **Realistic timing**: 5-minute buckets simulate realistic decision intervals
- **Easy strategy implementation**: Straightforward time-based logic
- **Portfolio tracking**: Simple aggregation across contracts

### Maintenance
- **No bitemporal complexity**: Eliminates transaction_time concerns
- **Clear data lineage**: One source of truth per time period
- **Simple data quality**: Easy to identify missing intervals

## Data Collection Implementation

### Time Bucket Calculation
```sql
-- Function to round timestamp to 5-minute boundary
-- 10:03:42 -> 10:00:00
-- 10:07:15 -> 10:05:00
SELECT
    DATE_TRUNC('hour', market_timestamp) +
    INTERVAL '5 minutes' * FLOOR(EXTRACT(MINUTE FROM market_timestamp) / 5)
    as time_bucket;
```

### Upsert Strategy
```sql
-- Insert or update pattern for real-time data collection
INSERT INTO option_chain_5min (symbol, time_bucket, mark, bid, ask, ...)
VALUES ('SPX250810C06410', '2025-08-01 10:00:00', 127.00, 125.80, 128.20, ...)
ON CONFLICT (symbol, time_bucket)
DO UPDATE SET
    mark = EXCLUDED.mark,
    bid = EXCLUDED.bid,
    ask = EXCLUDED.ask,
    updated_at = CURRENT_TIMESTAMP;
```

This time-series approach provides everything needed for effective options strategy backtesting while maintaining simplicity and performance.
