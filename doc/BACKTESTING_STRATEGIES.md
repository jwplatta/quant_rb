# Backtesting Strategies

This document outlines the backtesting framework for `lib/options_trader/backtest/` that enables testing strategies against historical market data with synthetic option chain generation.

## Architecture Overview

The backtesting system uses a **Service Adapter Pattern** that preserves existing search class APIs while providing historical data behind the scenes. This allows zero-code changes to existing strategy finders.

### Core Components

```
BacktestEngine
    ├── DataProviders::Schwab::HistoricalMarkets (data + option chains)
    ├── Services::BacktestMarkets (API adapter)
    ├── HistoricalDataIterator (streaming)
    └── Search Classes (unchanged)
```

## Component Details

### 1. DataProviders::Schwab::HistoricalMarkets

**Purpose**: Single provider that retrieves historical price data and generates synthetic option chains.

```ruby
module DataProviders
  module Schwab
    class HistoricalOptionsChain < Base
      def initialize(underlying_symbol:, start_datetime:, end_datetime:, interval: '5min', pricing_model: 'CRR', strike_step_size: 10)
        super()
        @underlying_symbol = underlying_symbol
        @start_datetime = start_datetime
        @end_datetime = end_datetime
        @interval = interval
        @underlying_price_history = fetch_underlying_price_history
        @pricing_model = pricing_model
        @strike_step_size = strike_step_size
      end

      def generate_option_quote(underlying_price:, current_datetime:, **kwargs)
        # NOTE: SchwabRb::DataObjects::QuotoFactory.build
        kwargs[:assetMainType]
      end

      def generate_option_chain(spot_price:, current_datetime:, **kwargs)
        # Uses Indicators::CoxRossRubinstein for option pricing
        # Returns Schwab API-compatible data structure
        # Single place for all option chain generation logic
        # strike_range
        # price =
      end

      def strike_range
        return @strike_range if defined?(@strike_range)

        spot_prices = @underlying_price_history.map { |candle| candle.close }
        avg_price = spot_prices.sum.to_f / spot_prices.size
        # TODO: parameterize the range size
        min_price = ((avg_price * 0.25) / 10).round * 10
        max_price = ((avg_price * 1.25) / 10).round * 10

        @strike_range = (min_price..max_price).step(@strike_step_size).to_a
        @strike_range
      end

      def backtest_iterator
        HistoricalOptionsChainIterator.new(self, @underlying_price_history)
      end

      def steps
        @steps ||= @underlying_price_history.map { |s| s.datetime }
      end

      private

      def fetch_underlying_price_history(symbol, start_datetime, end_datetime, interval)
        case interval
        when OptionsTrader::Intervals::ONE_MIN
          get_price_history_every_min(symbol: symbol, start_datetime: start_datetime, end_datetime: end_datetime)
        when OptionsTrader::Intervals::FIVE_MIN
          get_price_history_every_five_min(symbol: symbol, start_datetime: start_datetime, end_datetime: end_datetime)
        when OptionsTrader::Intervals::TEN_MIN
          get_price_history_every_ten_min(symbol: symbol, start_datetime: start_datetime, end_datetime: end_datetime)
        when OptionsTrader::Intervals::DAILY
          get_price_history_everyday(symbol: symbol, start_datetime: start_datetime, end_datetime: end_datetime)
        end
      end

      def get_price_history_every_min(symbol:, start_datetime:, end_datetime:)
      end

      def get_price_history_every_five_min(symbol:, start_datetime:, end_datetime:)
      end

      def get_price_history_every_ten_min(symbol:, start_datetime:, end_datetime:)
      end

      def get_price_history_everyday(symbol:, start_datetime:, end_datetime:)
      end

      def get_price_history(symbol, **kwargs)
        validate_symbol(symbol)

        kwargs = kwargs.merge({
          need_extended_hours_data: true,
          need_previous_close: false,
          return_data_objects: true
        })

        handle_api_errors("get_price_history") do
          client.get_price_history(symbol, **kwargs)
        end
      end
    end
  end
end
```

**Key Features**:
- Fetches historical data using existing `get_price_history_every_*` methods
- Generates synthetic option chains using Cox-Ross-Rubinstein model
- Single source of truth for both historical prices and option chain generation
- Manages time-series data efficiently with iterator pattern

### 2. HistoricalDataIterator

**Purpose**: Memory-efficient streaming of historical price data with lazy option chain calculation.

```ruby
module DataProviders
  module Schwab
    class HistoricalOptionsChainIterator
      include Enumerable

      def initialize(provider, historical_data)
        @provider = provider
        @historical_data = historical_data
      end

      def each
        return enum_for(:each) unless block_given?

        @historical_data.each do |candle|
          market_snapshot = {
            datetime: candle.datetime,
            underlying_price: candle.close,
            quote: ->(symbol = nil) {
              @provider.generate_quote(
                symbol: symbol,
                asset_type: asset_type
              )
            }
            option_chain: ->(pricing_model: 'CRR') {
              @provider.generate_option_chain(
                underlying_price: candle.close,
                current_datetime: candle.datetime,
                pricing_model: pricing_model
              )
            }
          }
          yield market_snapshot
        end
      end
    end
  end
end
```

**Key Features**:
- **Streaming** - processes one price point at a time
- **Lazy evaluation** - option chains calculated only when accessed via lambda
- **Memory efficient** - doesn't pre-calculate all option data

### 3. Services::BacktestMarkets

**Purpose**: Adapter that makes historical data look like live market data to search classes.

```ruby
module Services
  class BacktestOptionsChainMarkets
    def initialize(provider:)
      @provider = provider
      @current_snapshot = nil
    end

    def get_quote(symbol, **kwargs)
      return nil unless @current_snapshot

      # Use the current snapshot's price data
      # create_quote_from_snapshot(symbol, @current_snapshot)
      @current_snapshot[:quote].call()
    end

    # Duck typing - same interface as Services::Markets
    def get_option_chain(symbol, **kwargs)
      return nil unless @current_snapshot

      # Use the snapshot's lazy option chain
      @current_snapshot[:option_chain].call
    end

    # Set the current market snapshot directly
    def set_current_snapshot(snapshot)
      @current_snapshot = snapshot
    end
  end
end
```

**Key Features**:
- **Same API** as `Services::Markets` - search classes require zero changes
- **Snapshot-driven** - receives market snapshots directly from BacktestEngine
- **No dependencies** - doesn't need iterator or provider references
- **Lazy calculation** - option chains generated only when accessed via snapshot lambda

### 4. BacktestEngine

**Purpose**: Orchestrates the entire backtest execution, manages components, and runs strategy finding loops.

```ruby
@historical_provider = DataProviders::Schwab::HistoricalMarkets.new(
  underlying_symbol: underlying_symbol,
  start_datetime: start_date,
  end_datetime: end_date,
  interval: interval
)

class BacktestOptionsStrategy
  def initialize(underlying_symbol, start_date, end_date, provider:, interval: '5min')
    @iterator = @provider.market_data_iterator
    # Create the provider and pass it to the service object

    @portfolio = Portfolio.new(initial_balance: 100_000)
    @trade = nil
    @results = []
  end

  def run
    @iterator.each_with_index do |market_snapshot, index|
      @backtest_markets_service.set_current_snapshot(market_snapshot)

      if trade.nil?
        find_strategy(market_snapshot)
      else
        check_trade_progress(trade)
      end
      log_progress(index) if index % 100 == 0
    end

    generate_backtest_report
  end

  private

  def check_trade_progress(trade)
    # check the current price of the trade
    # if profit target reached, then exit and set trade = nil
    # if loss threshold reached, then exit and set trade = nil
  end

  def find_strategy(market_snapshot)
    strategy = StrategySearchFactory.find(
      markets_service: Services::BacktestMarkets.set_snapshot(market_snapshot), # <-- Same API as live trading!
      underlying_symbol: 'SPY',
      option_root: 'SPY',
      put_call: 'PUT',
      expiration_date: 30.days.from_now(market_snapshot[:datetime])
      short_delta: 0.15,
      max_spread: 5.0,
      min_credit: 0.25
    )

    if strategy && !strategy.is_a?(NullStrategy)
      @portfolio.enter_trade(strategy, market_snapshot[:datetime])
      @results << create_result_entry(strategy, market_snapshot)
    end
  end
end
```

**Key Features**:
- **Zero search class changes** - existing `VerticalSpreadSearch`, `IronCondorSearch` etc. work unchanged
- **Portfolio management** - tracks trades, P&L, buying power
- **Progress tracking** - logs backtest progress and results
- **Flexible timeframes** - supports minute, hourly, daily intervals

## Data Flow

```
1. BacktestEngine creates HistoricalMarkets provider and gets iterator
2. BacktestMarkets service created with no dependencies
3. For each market snapshot from iterator:
   a. BacktestEngine passes snapshot directly to service via set_current_snapshot()
   b. Search classes call get_option_chain() on BacktestMarkets service
   c. Service uses current snapshot's option_chain lambda
   d. Lambda calls provider's CoxRossRubinstein calculation
   e. Results returned in Schwab API format to search classes
4. Search classes find strategies using synthetic data
5. BacktestEngine processes results and advances to next snapshot
```

## Usage Examples

### Basic Backtest Setup

```ruby
# Create and run backtest
engine = OptionsStrategyBacktest.new(
  'SPY',
  Date.new(2023, 1, 1),
  Date.new(2023, 3, 31),
  interval: OptionsTrader::Intervals::DAILY,
  strategy: 'ironcondor',
  max_delta: 0.07,
  max_spread: 10.0,
  min_credit: 90.0,
  days_to_expiration: 7,
  exit_profit_threshold: 0.8, # 80% of credit received
  exit_loss_threshold: 3.0 # 3 times credit received
)

results = engine.run

# View results
puts "Average credit: $#{results.avg_credit}"
puts "Win rate: #{results.win_rate}%"
puts "Portfolio #{results.portfolio.to_s}"
```

## Performance Considerations

### Memory Usage
- **Iterator pattern** prevents loading entire dataset into memory
- **Lazy option chains** - calculated only when search classes need them
- **Streaming processing** - one time point processed at a time

### Computation Efficiency
- **Skip expensive calculations** when no trades possible (low buying power)
- **Conditional option chain generation** - only when search classes call `get_option_chain`
- **Batch processing** - process every Nth candle for faster backtests

## Key Benefits

- **Zero Code Changes**: Existing search classes (`VerticalSpreadSearch`, `IronCondorSearch`) work unchanged
- **Realistic Data**: Uses actual historical prices + mathematically calculated option chains
- **Memory Efficient**: Streaming iterator pattern prevents memory issues with large datasets
- **Time Accurate**: Each strategy search uses market data from exact historical moment
- **Extensible**: Easy to add new pricing models, data sources, or exit strategies
- **API Compatible**: Maintains same interface as live trading services