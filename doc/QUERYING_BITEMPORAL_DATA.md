# Querying Bitemporal Data

## Overview

A bitemporal database tracks data along two independent time dimensions: **valid time** (when the data was true in the real world) and **transaction time** (when the data was recorded in the database). This dual-time tracking enables powerful historical queries that can answer questions like "What did we know about employee salaries on March 1st?" or "What was John's actual salary during Q2, according to our records as of year-end?"

## Understanding the Two Time Dimensions

**Valid Time** represents the period during which a fact was true in reality. For example, if John's salary was $50,000 from January 1st to June 30th, that's the valid time period.

**Transaction Time** represents when the database became aware of this information. The same salary information might have been entered into the system on different dates due to processing delays, corrections, or retroactive updates.

## Basic Employee Salary Example

### Table Structure

```sql
CREATE TABLE employee_salary_bitemporal (
    employee_id INT,
    salary DECIMAL(10,2),
    valid_time_start DATE,
    valid_time_end DATE,
    transaction_time_start TIMESTAMP,
    transaction_time_end TIMESTAMP
);
```

### Sample Data

```sql
INSERT INTO employee_salary_bitemporal VALUES
-- John's salary records
(101, 45000, '2024-01-01', '2024-03-31', '2024-01-15 09:00:00', '2024-02-10 14:30:00'),
(101, 50000, '2024-04-01', '2024-12-31', '2024-02-10 14:30:00', '9999-12-31 23:59:59'),
(101, 47000, '2024-01-01', '2024-03-31', '2024-02-10 14:30:00', '9999-12-31 23:59:59'),

-- Mary's salary records
(102, 55000, '2024-01-01', '2024-06-30', '2024-01-20 10:00:00', '9999-12-31 23:59:59'),
(102, 60000, '2024-07-01', '2024-12-31', '2024-06-15 16:00:00', '9999-12-31 23:59:59');
```

### Common Query Patterns

#### Current State Query (As-Is Now)
```sql
SELECT employee_id, salary, valid_time_start, valid_time_end
FROM employee_salary_bitemporal
WHERE CURRENT_DATE BETWEEN valid_time_start AND valid_time_end
  AND CURRENT_TIMESTAMP BETWEEN transaction_time_start AND transaction_time_end;
```

#### Historical State Query (As-Was)
```sql
-- What did we know about salaries on February 1st, 2024?
SELECT employee_id, salary, valid_time_start, valid_time_end
FROM employee_salary_bitemporal
WHERE '2024-02-01 12:00:00' BETWEEN transaction_time_start AND transaction_time_end;
```

#### Point-in-Time Valid Data
```sql
-- What did we know on February 1st about salaries that were valid on March 15th?
SELECT employee_id, salary
FROM employee_salary_bitemporal
WHERE '2024-03-15' BETWEEN valid_time_start AND valid_time_end
  AND '2024-02-01 12:00:00' BETWEEN transaction_time_start AND transaction_time_end;
```

## Option Chain Bitemporal Example

### Schema Definition

Based on the Ruby migration for `option_chain_history` table:

```sql
CREATE TABLE option_chain_history (
    -- Contract identification
    symbol VARCHAR(255) NOT NULL,
    root_symbol VARCHAR(255),
    underlying_symbol VARCHAR(255) NOT NULL,
    expiration_date DATE NOT NULL,
    strike DECIMAL(10,2) NOT NULL,
    contract_type VARCHAR(10) NOT NULL,

    -- Pricing data
    bid DECIMAL(10,2),
    ask DECIMAL(10,2),
    mark DECIMAL(10,2),
    last_price DECIMAL(10,2),

    -- Underlying data
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

    -- Bitemporal timestamps
    valid_time TIMESTAMP NOT NULL,
    transaction_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

### Sample Option Data

$SPX CALL contract with strike 6410 expiring August 10th, 2025:

```sql
INSERT INTO option_chain_history (
    symbol, underlying_symbol, expiration_date, strike, contract_type,
    bid, ask, mark, last_price, underlying_price,
    delta, theta, vega, gamma, rho,
    open_interest, volume,
    valid_time, transaction_time
) VALUES
-- August 1st detailed intraday data
('SPX250810C06410', '$SPX', '2025-08-10', 6410.00, 'CALL',
 124.20, 126.80, 125.50, 125.00, 6532.15,
 0.64, -2.47, 8.95, 0.0046, 0.14,
 1250, 12,
 '2025-08-01 09:45:00', '2025-08-01 09:45:02'),

('SPX250810C06410', '$SPX', '2025-08-10', 6410.00, 'CALL',
 125.80, 128.20, 127.00, 126.50, 6538.92,
 0.65, -2.46, 8.92, 0.0045, 0.15,
 1250, 28,
 '2025-08-01 10:00:00', '2025-08-01 10:00:01'),

('SPX250810C06410', '$SPX', '2025-08-10', 6410.00, 'CALL',
 127.40, 129.60, 128.50, 128.25, 6544.33,
 0.66, -2.44, 8.88, 0.0044, 0.16,
 1250, 41,
 '2025-08-01 11:30:00', '2025-08-01 11:30:03'),

('SPX250810C06410', '$SPX', '2025-08-10', 6410.00, 'CALL',
 129.10, 131.40, 130.25, 129.80, 6548.76,
 0.67, -2.42, 8.84, 0.0043, 0.17,
 1250, 58,
 '2025-08-01 14:00:00', '2025-08-01 14:00:02'),

('SPX250810C06410', '$SPX', '2025-08-10', 6410.00, 'CALL',
 130.90, 133.20, 132.05, 131.60, 6552.41,
 0.68, -2.40, 8.81, 0.0042, 0.18,
 1250, 73,
 '2025-08-01 14:30:00', '2025-08-01 14:30:01'),

-- August 4th data
('SPX250810C06410', '$SPX', '2025-08-10', 6410.00, 'CALL',
 132.10, 134.60, 133.35, 133.00, 6548.92,
 0.67, -2.38, 8.76, 0.0043, 0.17,
 1245, 89,
 '2025-08-04 09:30:00', '2025-08-04 09:30:01'),

('SPX250810C06410', '$SPX', '2025-08-10', 6410.00, 'CALL',
 135.80, 138.20, 137.00, 136.45, 6555.33,
 0.68, -2.35, 8.69, 0.0042, 0.18,
 1245, 112,
 '2025-08-04 15:45:00', '2025-08-04 15:45:01');
```

## Specific Time-Based Queries

### Query 1: Price at 10:00 AM on August 1st

```sql
-- Get the exact price at 10:00 AM on August 1st
SELECT
    valid_time,
    mark,
    bid,
    ask,
    last_price,
    underlying_price,
    delta,
    volume
FROM option_chain_history
WHERE underlying_symbol = '$SPX'
  AND expiration_date = '2025-08-10'
  AND strike = 6410.00
  AND contract_type = 'CALL'
  AND valid_time = '2025-08-01 10:00:00';
```

**Result:**
- **Mark**: $127.00
- **Underlying**: $6,538.92
- **Delta**: 0.65

### Query 2: Price at 2:00 PM on August 1st

```sql
-- Get the exact price at 2:00 PM on August 1st
SELECT
    valid_time,
    mark,
    bid,
    ask,
    last_price,
    underlying_price,
    delta,
    volume
FROM option_chain_history
WHERE underlying_symbol = '$SPX'
  AND expiration_date = '2025-08-10'
  AND strike = 6410.00
  AND contract_type = 'CALL'
  AND valid_time = '2025-08-01 14:00:00';
```

**Result:**
- **Mark**: $130.25
- **Underlying**: $6,548.76
- **Delta**: 0.67

### Query 3: Daily Comparison (August 1st vs August 4th)

```sql
-- Get end-of-day marks for comparison
WITH daily_latest AS (
    SELECT
        DATE(valid_time) as trade_date,
        MAX(valid_time) as latest_time
    FROM option_chain_history
    WHERE underlying_symbol = '$SPX'
      AND expiration_date = '2025-08-10'
      AND strike = 6410.00
      AND contract_type = 'CALL'
      AND DATE(valid_time) IN ('2025-08-01', '2025-08-04')
    GROUP BY DATE(valid_time)
)
SELECT
    och.valid_time,
    dl.trade_date,
    och.mark,
    och.underlying_price,
    och.delta,
    och.volume
FROM option_chain_history och
JOIN daily_latest dl ON DATE(och.valid_time) = dl.trade_date
                     AND och.valid_time = dl.latest_time
WHERE och.underlying_symbol = '$SPX'
  AND och.expiration_date = '2025-08-10'
  AND och.strike = 6410.00
  AND och.contract_type = 'CALL'
ORDER BY och.valid_time;
```

### Query 4: Point-in-Time with Tolerance

```sql
-- Get the closest price data to 10:00 AM (within 15 minutes)
SELECT
    valid_time,
    mark,
    bid,
    ask,
    last_price,
    underlying_price,
    delta,
    ABS(EXTRACT(EPOCH FROM (valid_time - '2025-08-01 10:00:00'))) as seconds_from_target
FROM option_chain_history
WHERE underlying_symbol = '$SPX'
  AND expiration_date = '2025-08-10'
  AND strike = 6410.00
  AND contract_type = 'CALL'
  AND DATE(valid_time) = '2025-08-01'
  AND valid_time BETWEEN '2025-08-01 09:45:00' AND '2025-08-01 10:15:00'
ORDER BY seconds_from_target
LIMIT 1;
```

### Query 5: Intraday Price Evolution

```sql
-- Complete intraday timeline for August 1st
SELECT
    TIME(valid_time) as time_of_day,
    valid_time,
    mark,
    bid,
    ask,
    underlying_price,
    delta,
    volume,
    mark - LAG(mark) OVER (ORDER BY valid_time) as mark_change_from_previous
FROM option_chain_history
WHERE underlying_symbol = '$SPX'
  AND expiration_date = '2025-08-10'
  AND strike = 6410.00
  AND contract_type = 'CALL'
  AND DATE(valid_time) = '2025-08-01'
ORDER BY valid_time;
```

### Query 6: Time Comparison Analysis

```sql
-- Compare specific time points
WITH time_points AS (
    SELECT
        valid_time,
        mark,
        underlying_price,
        delta,
        CASE
            WHEN TIME(valid_time) = '10:00:00' THEN '10:00 AM'
            WHEN TIME(valid_time) = '14:00:00' THEN '2:00 PM'
        END as time_label
    FROM option_chain_history
    WHERE underlying_symbol = '$SPX'
      AND expiration_date = '2025-08-10'
      AND strike = 6410.00
      AND contract_type = 'CALL'
      AND valid_time IN ('2025-08-01 10:00:00', '2025-08-01 14:00:00')
)
SELECT
    time_label,
    valid_time,
    mark,
    underlying_price,
    delta,
    LAG(mark) OVER (ORDER BY valid_time) as previous_mark,
    mark - LAG(mark) OVER (ORDER BY valid_time) as mark_change,
    underlying_price - LAG(underlying_price) OVER (ORDER BY valid_time) as underlying_change
FROM time_points
ORDER BY valid_time;
```

### Query 7: Transaction Time vs Valid Time Analysis

```sql
-- Check recording delays for our specific time queries
SELECT
    valid_time,
    transaction_time,
    mark,
    EXTRACT(EPOCH FROM (transaction_time - valid_time)) as delay_seconds
FROM option_chain_history
WHERE underlying_symbol = '$SPX'
  AND expiration_date = '2025-08-10'
  AND strike = 6410.00
  AND contract_type = 'CALL'
  AND valid_time IN ('2025-08-01 10:00:00', '2025-08-01 14:00:00')
ORDER BY valid_time;
```

## Key Findings from Example

From our specific time queries for the $SPX CALL 6410 contract:

- **10:00 AM Mark**: $127.00 (underlying at $6,538.92)
- **2:00 PM Mark**: $130.25 (underlying at $6,548.76)
- **4-Hour Change**: +$3.25 in option mark (+$9.84 in underlying)
- **Delta Impact**: The option's delta increased from 0.65 to 0.67

## Benefits of Bitemporal Querying

This bitemporal approach enables:

1. **Audit Compliance**: Track exactly what data was available for decision-making at any point
2. **Error Correction**: Maintain historical accuracy while preserving the audit trail of changes
3. **Regulatory Reporting**: Generate reports showing data "as it was known" at specific reporting dates
4. **Temporal Analytics**: Analyze how understanding of business facts evolved over time
5. **Risk Management**: Understanding position values at specific times
6. **Trade Analysis**: Evaluating entry/exit timing decisions
7. **Strategy Backtesting**: Using precise historical option prices

The power of bitemporal databases lies in their ability to separate when something happened in reality from when the system learned about it, providing a complete and auditable view of how data and knowledge evolved over time.
