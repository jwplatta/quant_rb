# Create Local Backtest Database

## Description

We need to create a local postgres database to store backtesting data. The backtesting data is located at the path `/Volumes/ext_docs/options_trader/polygon/minute_aggs_v1`. This folder has sub folders representing the year, month, day. For example, the minute agg data for the September 29th, 2023 is in the `/Volumes/ext_docs/options_trader/polygon/minute_aggs_v1/2023/09/29` folder. We will only be using on the `SPXW.csv` data files in each of these folders. We will need to write a script that reads these csv files and then appropriately loads this data into the postgres database.

## Backtest Database

### Create Database Script

We will need to create the local postgres database and run the migrations before running the migration script.
- Write a bash script to create the database. The script should go in the `/bin` folder.
- The database should have the following details. See the development database in the database.yml
```sh
DATABASE_NAME_DEV='options_trader_db'
DATABASE_USER_DEV='options_trader'
DATABASE_PASSWORD_DEV='options_trader'
DATABASE_PORT_DEV=6543
DATABASE_HOST_DEV='localhost'
```
- When starting the database, the volume of the data should point to `/Volumes/ext_docs/options_trader/db`
```sh
initdb -D /path/to/external/drive/pgdata
```

### Start Database Script

Write short script in the `/bin` folder for starting the database the correct volume
```
pg_ctl -D /Volumes/ext_docs/options_trader/db -l /Volumes/ext_docs/options_trader/db/log start
```

### Migrations

We need to make some changes to the database table. You can use the generate migration rake task in `lib/tasks/generate.rake` to create the migration file.

- Add an index on the columns root_symbol and valid time
- Add an index on the symbol column
- Add a unique constraint on [:root_symbol, :expiration_date, :strike, :contract_type, :valid_time]

## Migration Script to Load the Data from CSV files

We'll create a `OptionsTrader::Services::PolygonSpxwImporter` class that has a single public method `import!`. It will have parameters for the root symbol, underlying symbol, year, month, day. The root and underlying symbols are a required parameters. The rest are optional.

If only the root and underlying symbols are provided then the script should import all the data for the root symbol. The import should be idempotent, i.e. trying to import it again will not update it or make a difference unless the record is explicitly deleted.

We'll then also create a rake task in `options_trader/tasks/polygon.rake` to run the importer.

This script will need to do the following:
- Loop over all the year, month, and day folders in the `/Volumes/ext_docs/options_trader/polygon/minute_aggs_v1` folder and read the `SPXW.csv` file
- For each row in the `SPXW.csv` we need to create a record in the `option_chain_history` table.
  - There should now be a unique constraint on [:root_symbol, :expiration_date, :strike, :contract_type, :valid_time]. So if the record already exists, the create record should fail. Rescue the error and proceed onto the next record
  - We will need to parse the following information from the option symbol in the csv file:
    - root_symbol
    - contract_type
    - strike
    - expiration_date
  - For example the ticker O:SPXW231006C04200000 contains Strike: 4200.0, Mark: 15.25, Volume: 150, Exp: 2023-10-06

```rb
ticker = row['ticker']
match = ticker.match(/^O:([A-Z]+)(\d{6})([CP])(\d{8})$/)
root_symbol, exp_date, put_or_call, strike_raw = match.captures

# Parse expiration date (YYMMDD -> Date)
exp_year = 2000 + exp_date[0..1].to_i
exp_month = exp_date[2..3].to_i
exp_day = exp_date[4..5].to_i
expiration_date = Date.new(exp_year, exp_month, exp_day)

strike_price = strike_raw.to_f / 1000.0
```
  - We will need to convert the `window_start` to

### Mapping of Headers in the SPXW.csv to the columns in option_chain_history table

Here are the columns in teh SPXW.csv file: ticker,volume,open,close,high,low,window_start,transactions. Below is the mapping to the columns in the option_chain_history table.

CSV HEADER -> COL NAME

```
ticker (remove the "O:" from the start of the ticker) -> symbol
root_symbol (extracted from ticker) -> root_symbol
contract_type (extracted from ticker) -> contract_type
strike (extracted from ticker) -> strike
expiration_date (extracted from ticker and converted to date) -> expiration_date
open -> open_price
close -> close_price
close -> mark
close -> last_price
high -> high_price
low -> low_price
volume -> volume
window_start (converted from unix nanosecond to timestamp) -> valid_time
```

