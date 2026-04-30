# SPX 1DTE Bot

Automated options trading bot for SPX 1 Day-To-Expiration (1DTE) iron condors.

## Dependencies

- Ruby 3.1.7
- schwab_rb 0.6.0
- Other dependencies managed via Bundler (see `Gemfile`)

## Setup

### 1. Prerequisites
- Schwab API credentials configured in root `.env` file
- Schwab token and account files in `~/.schwab_rb/`:
  - `token.json`
  - `account_names.json`
  - `account_hashes.json`

### 2. Environment Variables
Create `bots/.env` with:

```bash
SCHWAB_API_KEY='api_key'
SCHWAB_APP_SECRET='app_secret'
SCHWAB_TOKEN_PATH="~/.schwab_rb/token.json"
SCHWAB_APP_CALLBACK_URL='https://127.0.0.1:8182'
SPX_1DTE_ACCOUNT_NAME=ACCOUNT_NAME
SPX_1DTE_LOG_FILE=~/.options_trader/logs/spx_1dte_bot.log
SPX_1DTE_TRADES_FILE=~/.options_trader/trades/spx_1dte_trades.json
```
### 3. Configure the Bot Parameters

Edit `bots/config/spx_1dte.yml` to customize bot behavior:

```yaml
trade_mode: "paper"  # Options: "paper", "live"
account_name: "ALGO_TRADING_ACCOUNT"
trade:
  underlying_symbol: "$SPX"
  option_root: "SPXW"
  spread_width: 20
  min_credit: 1.25
  max_credit: 1.45
  target_delta: 0.7
  quantity: 1
  # ... see config file for all parameters
```

Key configuration sections:
- **trade_mode**: Set to "paper" for simulated trading or "live" for real trading
- **trade**: Iron condor parameters (deltas, credits, spread width, exit thresholds)
- **enter_trade_window**: When the bot will search for and enter new trades
- **monitoring_window**: When the bot monitors and manages open positions
- **high_risk_dates**: Dates to avoid opening new positions (FOMC, CPI, unemployment reports)
- **early_close_dates**: Days when market closes early
- **holiday_dates**: Market holidays when bot should not trade

### 4. Create Log and Trade Directories
```bash
mkdir -p ~/.options_trader/bots ~/.options_trader/trades
touch ~/.options_trader/trades/spx_1dte_trades.json
echo '{"trades": []}' > ~/.options_trader/trades/spx_1dte_trades.json
```

## Run Bot

### Local Machine

```bash
# Install dependencies
bundle install

# Run the bot
bundle exec ruby bots/spx_1dte.rb
```

The bot will:
- Load configuration from `bots/config/spx_1dte.yml`
- Use environment variables from `bots/.env`
- Write logs to the path specified in `SPX_1DTE_LOG_FILE`
- Track trades in the file specified in `SPX_1DTE_TRADES_FILE`

### Docker

```bash
# Start bot
docker-compose up -d spx_1dte_bot

# View logs (live tail)
docker-compose logs -f spx_1dte_bot

# Or tail from host
tail -f ~/.options_trader/bots/spx_1dte_bot.log

# Stop bot
docker-compose stop spx_1dte_bot

# Restart bot
docker-compose restart spx_1dte_bot

# Rebuild and restart (after code changes)
docker-compose up -d --build spx_1dte_bot
```

## Debugging

### Local Machine

### Docker
```bash
# Check if container is running
docker ps | grep spx_1dte_bot

# View recent logs (last 50 lines)
docker-compose logs --tail=50 spx_1dte_bot

# SSH into running container
docker-compose exec spx_1dte_bot bash

# Run a one-off command in container
docker-compose run --rm spx_1dte_bot bash

# Check environment variables
docker-compose exec spx_1dte_bot printenv | grep SPX

# View container resource usage
docker stats options_trader-spx_1dte_bot-1

# Inspect container configuration
docker inspect options_trader-spx_1dte_bot-1
```

## File Locations

**Host Machine:**
- Logs: `~/.options_trader/logs/spx_1dte_bot.log`
- Trades: `~/.options_trader/trades/spx_1dte_trades.json`

**Inside Container:**
- Logs: `/app/logs/spx_1dte_bot.log`
- Trades: `/app/trades/spx_1dte_trades.json`
