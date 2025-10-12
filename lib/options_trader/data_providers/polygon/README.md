# Using Polgyon to Backtest

## Notes

- You have the flat file with the minute by minute prices for each contract
- However, you will need to get `/v3/reference/options/contracts/{options_ticker}`
  - strike price on the contract
  - expiration date on the contract
  - contract type
- You will also need to get the underlying price using the schwab API or something

## Endpoints


- Use `/v3/reference/options/contracts` to get all the contracts available for an expiration date.
  - Params
    - `as_of`
    - `expiration_date`
    - `contract_type`
    - `strike_price.gte` and `strike_price.lte`
    - `limit` set to 1000
- Use `/v2/aggs/ticker/{optionsTicker}/range/{multiplier}/{timespan}/{from}/{to}`