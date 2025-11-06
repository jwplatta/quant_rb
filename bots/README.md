# SPX 1DTE Bot

Automated options trading bot for SPX 1 Day-To-Expiration (1DTE) iron condors.

## Setup

### 1. Prerequisites
- Schwab API credentials configured in root `.env` file
- Schwab token and account files in `~/.schwab_rb/`:
  - `token.json`
  - `account_names.json`
  - `account_hashes.json`

### 2. Configure Bot
Create `bots/.env` with:
```bash
SPX_1DTE_ACCOUNT_NAME=TRADING_BROKERAGE_ACCOUNT  # Your Schwab account name
SPX_1DTE_LOG_FILE=/app/logs/spx_1dte_bot.log
SPX_1DTE_TRADES_FILE=/app/trades/spx_1dte_trades.json
```

### 3. Create Log and Trade Directories
```bash
mkdir -p ~/.options_trader/bots ~/.options_trader/trades
touch ~/.options_trader/trades/spx_1dte_trades.json
echo '{"trades": []}' > ~/.options_trader/trades/spx_1dte_trades.json
```

## Running

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
- Logs: `~/.options_trader/bots/spx_1dte_bot.log`
- Trades: `~/.options_trader/trades/spx_1dte_trades.json`

**Inside Container:**
- Logs: `/app/logs/spx_1dte_bot.log`
- Trades: `/app/trades/spx_1dte_trades.json`

## Trade Window

The bot operates during market hours:
- Trade entry: 2:59 PM - 3:15 PM CT
- Trade monitoring: Continuous during market hours
- Exit conditions: 11:00 AM CT or profit/loss thresholds

