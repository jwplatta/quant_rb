# Bots README

## 

## Overview
The bots in this folder are designed to automate trading operations. They consist of several components that work together to poll market conditions, handle trade events, and execute trading strategies. Below is an explanation of how the implementation works.

## Components

### 1. `BotBase`
This is the base class for all bots. It provides common functionality such as:
- **File Management**: Handles reading, saving, and deleting trade files.
- **Event Queue**: Manages a queue for trade events.
- **Poller and Handler**: Initializes and starts the `MarketPoller` and `EventHandler`.
- **Abstract Methods**: Defines methods like `find_trade`, `send_order`, `trade_file`, and `order_history_file` that must be implemented by subclasses.

### 2. `MarketPoller`
The `MarketPoller` class is responsible for:
- **Polling**: Periodically checks market conditions and the status of trades.
- **Event Generation**: Pushes events to the queue based on trade status (e.g., `:find_trade`, `:order_filled`, `:order_failed`, `:market_changed`).
- **Error Handling**: Captures errors and pushes them as events.

### 3. `EventHandler`
The `EventHandler` class processes events from the queue and performs actions such as:
- **Finding Trades**: Calls the bot's `find_trade` method to identify new trading opportunities.
- **Order Management**: Handles events like `:order_filled`, `:order_failed`, and `:market_changed`.
- **Market Adjustments**: Responds to changing market conditions by replacing or adjusting trades.
- **Error Handling**: Logs errors and their stack traces.

### 4. `TradeEvent`
The `TradeEvent` class represents events in the trading system. Each event has:
- **Type**: The type of event (e.g., `:find_trade`, `:order_filled`).
- **Payload**: Additional data associated with the event (e.g., trade details).

### 5. `WeeklySPX`
This is a specific bot implementation for trading SPX options weekly. It extends `BotBase` and provides:
- **Trade Finder**: Searches for trades using specific criteria like `max_spread`, `min_credit`, and `short_delta`.
- **Order Execution**: Sends orders and monitors their progress.
- **Market Condition Checks**: Determines if market conditions have changed.
- **Thresholds**: Implements loss and profit thresholds for exiting trades.

## Workflow
1. **Initialization**: The bot initializes the `MarketPoller` and `EventHandler`.
2. **Polling**: The `MarketPoller` periodically checks market conditions and trade statuses.
3. **Event Handling**: The `EventHandler` processes events and performs actions like finding trades, sending orders, or adjusting trades.
4. **Trade Execution**: Trades are executed based on predefined criteria and monitored for progress.
5. **Error Handling**: Errors are captured and logged, ensuring the bot continues running.

## Extending the Bots
To create a new bot:
1. Extend the `BotBase` class.
2. Implement the required methods (`find_trade`, `send_order`, etc.).
3. Define specific trade criteria and thresholds.

## Notes
- Ensure the environment variables are set correctly (e.g., `TRADES_DIR`).
- Subclasses must implement abstract methods in `BotBase`.
- Use the `TRADE_FILE` and `ORDER_HISTORY_FILE` constants for file management.