WITH options AS (
  SELECT DISTINCT ON (symbol) symbol,
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
  WHERE expiration_date = '2025-08-11'
  AND valid_time > '2025-08-08 20:10:00 -0500'
  AND valid_time <= '2025-08-08 20:30:00 -0500'
  AND mark > 0
  AND source = 'polygon'
  ORDER BY symbol, valid_time DESC)

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
  LIMIT 1)
underlying ON true ORDER BY options.strike;