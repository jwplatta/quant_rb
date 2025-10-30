WITH options AS (
  SELECT DISTINCT ON (symbol)
    symbol,
    (expiration_date::date - valid_time::date) AS dte,
    strike,
    contract_type,
    expiration_date,
    mark,
    underlying_price,
    volume,
    open_price,
    close_price,
    high_price,
    low_price,
    valid_time
  FROM option_chain_history
  WHERE expiration_date = '2025-02-20'
    AND valid_time <= '2025-02-19 20:59:00 UTC'
    AND valid_time > '2025-02-19 20:54:00 UTC'
    AND contract_type = 'PUT'
    AND source = 'polygon'
  ORDER BY symbol, valid_time DESC
),
features AS (
  SELECT
    MAX(CASE WHEN symbol = '$VIX9D' THEN close END) as vix9d,
    MAX(CASE WHEN symbol = '$VVIX' THEN close END) as vvix
  FROM (
    SELECT DISTINCT ON (symbol) symbol, close
    FROM price_history
    WHERE symbol IN ('$VIX9D', '$VVIX')
      AND valid_time <= '2025-02-19 20:59:00 UTC'
      AND valid_time > '2025-02-19 20:54:00'
    ORDER BY symbol, valid_time DESC
  ) latest
)
SELECT
  options.symbol,
  options.strike,
  options.contract_type,
  options.expiration_date,
  options.mark,
  options.volume,
  options.open_price,
  options.close_price,
  options.high_price,
  options.low_price,
  options.valid_time,
  options.dte,
  underlying.close as underlying_price,
  options.strike / underlying.close::float as moneyness,
            features.vix9d,
            features.vvix
FROM options
LEFT JOIN LATERAL (
  SELECT close, valid_time
  FROM price_history
  WHERE symbol = '$SPX'
    AND valid_time <= options.valid_time
  ORDER BY valid_time DESC
  LIMIT 1
) underlying ON true
CROSS JOIN features
WHERE options.strike / underlying.close::float <= 1.01
ORDER BY options.strike;

WITH options AS (
  SELECT DISTINCT ON (symbol)
    symbol,
    (expiration_date::date - valid_time::date) AS dte,
    strike,
    contract_type,
    expiration_date,
    mark,
    underlying_price,
    volume,
    open_price,
    close_price,
    high_price,
    low_price,
    valid_time
  FROM option_chain_history
  WHERE expiration_date = '2025-02-20'
    AND valid_time <= '2025-02-19 20:59:00 UTC'
    AND valid_time > '2025-02-19 20:54:00'
    AND contract_type = 'PUT'
    AND source = 'polygon'
  ORDER BY symbol, valid_time DESC
)

SELECT
  options.symbol,
  options.strike,
  options.contract_type,
  options.expiration_date,
  underlying.close as underlying_price
FROM options
LEFT JOIN LATERAL (
  SELECT close, valid_time
  FROM price_history
  WHERE symbol = '$SPX'
    AND valid_time <= options.valid_time
  ORDER BY valid_time DESC
  LIMIT 1
) underlying ON true
WHERE options.strike / underlying.close::float <= 1.01
ORDER BY options.strike;


WITH options AS (
  SELECT DISTINCT ON (symbol)
    symbol,
    strike,
    contract_type,
    expiration_date,
    mark,
    underlying_price,
    volume,
    open_price,
    close_price,
    high_price,
    low_price,
    valid_time
  FROM option_chain_history
  WHERE expiration_date = '2025-02-20'
    AND valid_time <= '2025-02-19 20:59:00 UTC'
    AND valid_time > '2025-02-19 20:54:00 UTC'
    AND source = 'polygon'
  ORDER BY symbol, valid_time DESC
)

SELECT
  options.*,
  underlying.close as underlying_price
FROM options
LEFT JOIN LATERAL (
  SELECT close, valid_time
  FROM price_history
  WHERE symbol = '$SPX'
    AND valid_time <= options.valid_time
  ORDER BY valid_time DESC
  LIMIT 1
) underlying ON true
ORDER BY options.strike;

-- - For Calls: `extrinsic value = mark - (underlying_price - strike)`

SELECT DISTINCT ON (symbol)
    symbol,
    strike,
    contract_type,
    expiration_date,
    CASE
      WHEN strike >= 4594 THEN close_price
      WHEN strike < 4594 THEN close_price - (4594 - strike)
    END AS extrinsic_value,
    CASE
      WHEN strike >= 4594 THEN 0
      WHEN strike < 4594 THEN (4594 - strike)
    END AS intrinsic_value,
    volume,
    open_price,
    close_price,
    high_price,
    low_price,
    valid_time
  FROM option_chain_history
  WHERE expiration_date = '2023-12-04'
    AND valid_time <= '2023-12-01 20:59:00 UTC'
    AND valid_time > '2023-12-01 20:54:00 UTC'
    AND source = 'polygon'
    AND contract_type = 'CALL'
  ORDER BY symbol, valid_time DESC;

  -- 4594


SELECT DISTINCT ON (symbol)
    strike,
    CASE
      WHEN strike >= 4594 THEN close_price
      WHEN strike < 4594 THEN close_price - (4594 - strike)
    END AS extrinsic_value
  FROM option_chain_history
  WHERE expiration_date = '2023-12-04'
    AND valid_time <= '2023-12-01 20:59:00 UTC'
    AND valid_time > '2023-12-01 20:54:00 UTC'
    AND source = 'polygon'
    AND contract_type = 'CALL'
  ORDER BY symbol, valid_time DESC;

strike  | extrinsic_value
---------+-----------------
 4530.00, |         
 4555.00, |
 4565.00, |
 4570.00, |
 4575.00, |
 4580.00, |
 4585.00, |
 4590.00, |
 4595.00, |
 4600.00, |
 4605.00, |
 4610.00, |
 4615.00, |
 4620.00, |
 4625.00, |
 4630.00, |
 4635.00, |
 4640.00, |
 4645.00, |
 4650.00, |
 4655.00, |
 4660.00, |
 4665.00, |
 4670.00, |
 4675.00, |
 4680.00, |
 4685.00, |
 4690.00, |
 4695.00, |
 4700.00, |
 4710.00, |
 4720.00, |
 4740.00, |
 4750.00, |
 4775.00, |