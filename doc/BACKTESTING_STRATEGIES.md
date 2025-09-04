# Backtesting Strategies

This document outlines a streamlined backtesting framework for `lib/options_trader/backtest/` that allows seamless switching between live and backtest modes.

## Notes

- Keep Schwab client for historical data retrieval
- Override specific Schwab methods (`quote`, `option_chain`) to return synthetic data
- Disable certain methods (`transactions`, `place_order`) in backtest mode
- Focus on strategy finding using existing search module
- Global backtest flag controls behavior

## Goal

Enable backtesting by simply wrapping existing strategies/trades/bots or setting a boolean flag. The framework should:
1. Work with existing code without modification
2. Provide historical data in place of live market data
3. Simulate order execution instead of sending to broker
4. Generate synthetic option chains using the indicators module

## Core Design Patterns

We'll use just **3 key patterns** to keep it simple and maintainable:

### 1. Global Backtest Configuration

Add global configuration to control backtest mode throughout the system.

```ruby
module OptionsTrader
  # Global backtest configuration
  class << self
    attr_accessor :backtest_mode, :backtest_current_time, :backtest_volatility

    def toggle_backtest
      if backtest
        @backtest_mode = false
      else
        @backtest_mode = true
      end
    end

    def backtest?
      @backtest_mode || false
    end
  end
end
```

### 2. Override Schwab Methods for Backtest Mode

Modify the Schwab module to use synthetic data when in backtest mode.

```ruby
module OptionsTrader::Schwab
  # Keep original client for historical data retrieval
  # Override specific methods for backtest mode

  def quote(symbol)
    if OptionsTrader.backtest?
      # Get historical price for current backtest time
      price = get_historical_price_at_time(symbol, OptionsTrader.backtest_current_time)
      create_synthetic_quote(symbol, price)
    else
      # Original live quote method
      client.get_quote(symbol, return_data_objects: true)
    end
  end

  def quotes(symbols)
    if OptionsTrader.backtest?
      symbols.map { |symbol| quote(symbol) }
    else
      # Original live quotes method
      client.get_quotes(symbols, return_data_objects: true)
    end
  end

  def option_chain(symbol, **kwargs)
    if OptionsTrader.backtest?
      # Get historical underlying price
      underlying_price = get_historical_price_at_time(symbol, OptionsTrader.backtest_current_time)

      # Generate synthetic option chain using indicators
      generate_synthetic_option_chain(symbol, underlying_price, **kwargs)
    else
      # Original live option chain method
      client.get_option_chain(symbol, **kwargs)
    end
  end

  # Disable these methods in backtest mode
  def transactions(*)
    return [] if OptionsTrader.backtest_mode?
    super
  end

  def transaction(*)
    return nil if OptionsTrader.backtest_mode?
    super
  end

  def place_order(*)
    if OptionsTrader.backtest_mode?
      # Log simulated order execution
      puts "BACKTEST: Order execution simulated"
      return OpenStruct.new(status: 201, order_id: "BACKTEST_#{Time.now.to_i}")
    else
      super
    end
  end

  private

  def get_historical_price_at_time(symbol, timestamp)
    # Use existing price_history_every_minute to get data around timestamp
    start_time = timestamp - 1.minute
    end_time = timestamp + 1.minute

    history = price_history_every_minute(symbol, start_time, end_time)

    # Find closest candle to target time
    closest_candle = history.candles.min_by { |candle| (candle.datetime - timestamp).abs }
    closest_candle&.close || 0
  end

  def create_synthetic_quote(symbol, price)
    # Create quote object matching Schwab API format
    OpenStruct.new(
      symbol: symbol,
      bid: price - 0.01,
      ask: price + 0.01,
      last: price,
      mark: price,
      close_price: price
    )
  end

  def generate_synthetic_option_chain(symbol, underlying_price, **kwargs)
    expiration_date = kwargs[:to_date] || kwargs[:from_date] || (Date.current + 7.days)
    time_to_expiry = (expiration_date.to_date - OptionsTrader.backtest_current_time.to_date).to_f / 365

    return nil if time_to_expiry <= 0

    # Generate realistic strike range around current price
    strikes = generate_strikes(underlying_price)

    call_options = strikes.map do |strike|
      call_price = OptionsTrader::Indicators::BlackScholes.calculate(
        spot_price: underlying_price,
        strike_price: strike,
        time_to_expiry: time_to_expiry,
        risk_free_rate: 0.05,
        volatility: OptionsTrader.backtest_volatility,
        option_type: OptionsTrader::CALL
      )

      delta = OptionsTrader::Indicators::Greeks::Delta.calculate(
        spot_price: underlying_price,
        strike_price: strike,
        time_to_expiry: time_to_expiry,
        risk_free_rate: 0.05,
        volatility: OptionsTrader.backtest_volatility,
        option_type: OptionsTrader::CALL
      )

      create_synthetic_option('CALL', symbol, strike, expiration_date, call_price, delta)
    end

    put_options = strikes.map do |strike|
      put_price = OptionsTrader::Indicators::BlackScholes.calculate(
        spot_price: underlying_price,
        strike_price: strike,
        time_to_expiry: time_to_expiry,
        risk_free_rate: 0.05,
        volatility: OptionsTrader.backtest_volatility,
        option_type: OptionsTrader::PUT
      )

      delta = OptionsTrader::Indicators::Greeks::Delta.calculate(
        spot_price: underlying_price,
        strike_price: strike,
        time_to_expiry: time_to_expiry,
        risk_free_rate: 0.05,
        volatility: OptionsTrader.backtest_volatility,
        option_type: OptionsTrader::PUT
      )

      create_synthetic_option('PUT', symbol, strike, expiration_date, put_price, delta)
    end

    # Return in Schwab API format
    format_option_chain_response(symbol, expiration_date, call_options, put_options)
  end

  def generate_strikes(underlying_price)
    # Generate strikes from 80% to 120% of underlying price in $5 increments
    start_strike = (underlying_price * 0.8 / 5).floor * 5
    end_strike = (underlying_price * 1.2 / 5).ceil * 5
    (start_strike..end_strike).step(5).to_a
  end

  def create_synthetic_option(put_call, symbol, strike, expiration_date, theoretical_price, delta)
    # Add bid/ask spread around theoretical price
    spread = theoretical_price * 0.02 # 2% spread
    bid = [(theoretical_price - spread/2), 0.05].max.round(2)
    ask = (theoretical_price + spread/2).round(2)

    OpenStruct.new(
      symbol: "#{symbol}_#{expiration_date.strftime('%m%d%y')}#{put_call[0]}#{strike.to_i}",
      put_call: put_call,
      strike_price: strike,
      expiration_date: expiration_date,
      bid: bid,
      ask: ask,
      last: theoretical_price.round(2),
      mark: ((bid + ask) / 2).round(2),
      delta: delta.round(4),
      open_interest: rand(100..1000), # Random but realistic
      volume: rand(10..100)
    )
  end

  def format_option_chain_response(symbol, expiration_date, call_options, put_options)
    # Format to match Schwab API structure
    OpenStruct.new(
      symbol: symbol,
      status: 'SUCCESS',
      call_exp_date_map: {
        expiration_date.strftime('%Y-%m-%d:%d') => call_options.group_by(&:strike_price)
      },
      put_exp_date_map: {
        expiration_date.strftime('%Y-%m-%d:%d') => put_options.group_by(&:strike_price)
      }
    )
  end
end
```

### 3. Backtest DSL for Strategy Finding

Simple DSL to configure and run strategy backtests.

```ruby
module OptionsTrader::Backtest
  def self.run(&block)
    config = BacktestConfig.new
    config.instance_eval(&block)

    runner = BacktestRunner.new(config)
    runner.execute
  end

  class BacktestConfig
    attr_accessor :backtest_type, :step_frequency, :start_date, :end_date,
                  :symbol, :max_delta, :min_credit, :max_spread,
                  :min_open_interest, :increment, :days_to_expiration,
                  :strategy_type, :put_call, :option_root, :settlement_type

    def initialize
      @backtest_type = :strategy
      @step_frequency = :daily
      @strategy_type = 'ironcondor'
    end

    def backtest(type)
      @backtest_type = type
    end

    def step(frequency)
      @step_frequency = frequency
    end

    def start_date(date)
      @start_date = Date.parse(date.to_s)
    end

    def end_date(date)
      @end_date = Date.parse(date.to_s)
    end

    def symbol(sym)
      @symbol = sym
    end

    def max_delta(delta)
      @max_delta = delta
    end

    def min_credit(credit)
      @min_credit = credit
    end

    def max_spread(spread)
      @max_spread = spread
    end

    def min_open_interest(oi)
      @min_open_interest = oi
    end

    def increment(inc)
      @increment = inc
    end

    def days_to_expiration(days)
      @days_to_expiration = days
    end

    def strategy_type(type)
      @strategy_type = type
    end

    def put_call(pc)
      @put_call = pc
    end

    def option_root(root)
      @option_root = root
    end

    def settlement_type(type)
      @settlement_type = type
    end

    def to_search_params
      {
        strategy_type: @strategy_type,
        underlying_symbol: @symbol,
        expiration_date: calculate_expiration_date,
        option_root: @option_root,
        put_call: @put_call,
        settlement_type: @settlement_type,
        short_delta: @max_delta,
        max_spread: @max_spread,
        min_credit: @min_credit,
        min_open_interest: @min_open_interest,
        increment: @increment
      }.compact
    end

    private

    def calculate_expiration_date
      return nil unless @days_to_expiration
      Date.current + @days_to_expiration.days
    end
  end

  class BacktestRunner
    def initialize(config)
      @config = config
      @results = []
    end

    def execute
      puts "Starting #{@config.backtest_type} backtest for #{@config.symbol}"
      puts "Period: #{@config.start_date} to #{@config.end_date}"
      puts "Frequency: #{@config.step_frequency}"

      case @config.backtest_type
      when :strategy
        run_strategy_backtest
      when :trade
        run_trade_backtest
      when :bot
        run_bot_backtest
      end

      BacktestResults.new(@results, @config)
    end

    private

    def run_strategy_backtest
      time_periods = generate_time_periods

      time_periods.each_with_index do |timestamp, index|
        puts "#{index + 1}/#{time_periods.count}: #{timestamp.strftime('%Y-%m-%d %H:%M')}"

        # Enable backtest mode for this timestamp
        OptionsTrader.enable_backtest(timestamp, volatility: 0.20)

        begin
          # Find strategy using existing search module
          strategy = OptionsTrader::StrategySearchFactory.find(@config.to_search_params)

          if strategy && !strategy.is_a?(OptionsTrader::NullStrategy)
            result = {
              timestamp: timestamp,
              strategy_type: strategy.type,
              strategy_data: strategy.to_h,
              credit: strategy.credit,
              delta: strategy.delta,
              underlying_price: get_current_underlying_price
            }

            @results << result
            puts "  ✓ Found #{strategy.type}: Credit: #{strategy.credit}, Delta: #{strategy.delta}"
          else
            puts "  ✗ No strategy found"
          end
        rescue => e
          puts "  ⚠ Error: #{e.message}"
        ensure
          OptionsTrader.disable_backtest
        end
      end
    end

    def run_trade_backtest
      # TODO: Implement trade backtesting
      puts "Trade backtesting not yet implemented"
    end

    def run_bot_backtest
      # TODO: Implement bot backtesting
      puts "Bot backtesting not yet implemented"
    end

    def generate_time_periods
      case @config.step_frequency
      when :minute
        generate_minute_periods
      when :five_minutes
        generate_five_minute_periods
      when :ten_minutes
        generate_ten_minute_periods
      when :hourly
        generate_hourly_periods
      when :daily
        generate_daily_periods
      when :weekly
        generate_weekly_periods
      else
        [(@config.start_date + 9.hours + 30.minutes).to_time] # Default: 9:30 AM on start date
      end
    end

    def generate_daily_periods
      (@config.start_date..@config.end_date).map do |date|
        # 9:30 AM ET each day
        (date.to_time + 9.hours + 30.minutes)
      end
    end

    def generate_hourly_periods
      periods = []
      current = (@config.start_date.to_time + 9.hours + 30.minutes) # Start at 9:30 AM
      end_time = (@config.end_date.to_time + 16.hours) # End at 4:00 PM

      while current <= end_time
        # Only include market hours (9:30 AM - 4:00 PM ET on weekdays)
        if current.wday.between?(1, 5) && current.hour.between?(9, 15)
          if current.hour > 9 || (current.hour == 9 && current.min >= 30)
            periods << current
          end
        end
        current += 1.hour
      end

      periods
    end

    def generate_minute_periods
      # This could generate a lot of data points - be careful with date ranges
      periods = []
      current = (@config.start_date.to_time + 9.hours + 30.minutes)
      end_time = (@config.end_date.to_time + 16.hours)

      while current <= end_time
        if current.wday.between?(1, 5) && current.hour.between?(9, 15)
          if current.hour > 9 || (current.hour == 9 && current.min >= 30)
            periods << current
          end
        end
        current += 1.minute
      end

      periods.first(1000) # Limit to prevent excessive API calls
    end

    def generate_five_minute_periods
      generate_minute_periods.select.with_index { |_, i| i % 5 == 0 }
    end

    def generate_ten_minute_periods
      generate_minute_periods.select.with_index { |_, i| i % 10 == 0 }
    end

    def generate_weekly_periods
      (@config.start_date..@config.end_date).step(7).map do |date|
        # 9:30 AM ET each week
        (date.to_time + 9.hours + 30.minutes)
      end
    end

    def get_current_underlying_price
      # This will use the overridden quote method which returns historical data
      quote_data = Object.new.extend(OptionsTrader::Schwab).quote(@config.symbol)
      quote_data.last
    end
  end

  class BacktestResults
    attr_reader :strategies_found, :success_rate, :avg_credit, :config

    def initialize(results, config)
      @results = results
      @config = config
      calculate_metrics
    end

    def strategies_found
      @results.count
    end

    def strategy_types
      @results.group_by { |r| r[:strategy_type] }.transform_values(&:count)
    end

    def credits
      @results.map { |r| r[:credit] }
    end

    def summary
      puts "\n" + "="*50
      puts "BACKTEST RESULTS"
      puts "="*50
      puts "Symbol: #{@config.symbol}"
      puts "Period: #{@config.start_date} to #{@config.end_date}"
      puts "Frequency: #{@config.step_frequency}"
      puts "Strategy Type: #{@config.strategy_type}"
      puts ""
      puts "Strategies Found: #{strategies_found}"
      puts "Success Rate: #{@success_rate}%" if @success_rate
      puts "Average Credit: $#{@avg_credit}" if @avg_credit
      puts ""

      if strategy_types.any?
        puts "Strategy Breakdown:"
        strategy_types.each do |type, count|
          puts "  #{type}: #{count}"
        end
      end

      puts "="*50
    end

    private

    def calculate_metrics
      return if @results.empty?

      @avg_credit = (@results.sum { |r| r[:credit] } / @results.count.to_f).round(2)
      # Success rate would need total attempts to calculate properly
    end
  end
end
```

### 1. Daily Iron Condor Backtest

```ruby
results = OptionsTrader::Backtest.run do
  # Test configuration
  backtest :strategy
  step :daily
  start_date '2025-08-01'
  end_date '2025-08-30'

  # Strategy configuration
  strategy_type 'ironcondor'
  symbol '$SPX'
  max_delta 0.15
  min_credit 100
  max_spread 20
  min_open_interest 10
  increment 0.05
  days_to_expiration 7
end

results.summary
```

### 2. Hourly Put Spread Search

```ruby
OptionsTrader::Backtest.run do
  # Test configuration
  backtest :strategy
  step :hourly
  start_date Date.current
  end_date Date.current

  # Strategy configuration
  strategy_type 'vertical'
  put_call 'PUT'
  symbol '$SPX'
  max_delta 0.20
  min_credit 50
  days_to_expiration 3
end
```

### 3. Weekly Single Option Search

```ruby
OptionsTrader::Backtest.run do
  backtest :strategy
  step :weekly
  start_date '2025-01-01'
  end_date '2025-12-31'

  strategy_type 'single'
  put_call 'CALL'
  symbol '$SPX'
  max_delta 0.30
  min_credit 25
  days_to_expiration 14
end
```

### 4. High Frequency Minute-by-Minute

```ruby
# Be careful with date ranges for minute frequency!
OptionsTrader::Backtest.run do
  backtest :strategy
  step :minute
  start_date '2025-08-15'
  end_date '2025-08-15'  # Single day only

  strategy_type 'ironcondor'
  symbol '$SPX'
  max_delta 0.10
  min_credit 150
  max_spread 15
  days_to_expiration 1  # 0DTE strategies
end
```

## Implementation Checklist (MVP)

### Phase 1: Global Configuration
- [ ] Add global backtest flag to main OptionsTrader module
- [ ] Implement `backtest?` and `toggle_backtest` methods
- [ ] Add `backtest_current_time` and `backtest_volatility` attributes

### Phase 2: Schwab Method Overrides
- [ ] Override `quote`, `quotes`, and `option_chain` methods with backtest mode checks
- [ ] Implement `get_historical_price_at_time` using existing `price_history_every_minute`
- [ ] Create `create_synthetic_quote` to match Schwab API format

### Phase 3: Synthetic Option Chain
- [ ] Implement `generate_synthetic_option_chain` method
- [ ] Create `generate_strikes` for realistic strike prices
- [ ] Build `create_synthetic_option` with bid/ask spreads and delta
- [ ] Format chains to match Schwab API (`format_option_chain_response`)

### Phase 4: DSL Framework
- [ ] Create `OptionsTrader::Backtest.run` method
- [ ] Implement `BacktestConfig` with DSL methods (`step`, `symbol`, `max_delta`, etc.)
- [ ] Build `BacktestRunner` with time period generation
- [ ] Connect to existing `StrategySearchFactory.find`

### Phase 5: Basic Results
- [ ] Implement `BacktestResults` with strategy count and average credit
- [ ] Create simple text summary output
- [ ] Test with existing search modules (`IronCondorSearch`, etc.)

That's it! Everything else can be added later as needed.

## Key Benefits

- **Zero Code Changes**: Existing strategies, bots, and trades work unchanged
- **Simple Toggle**: Single boolean flag switches between live and backtest modes
- **Realistic Data**: Uses actual historical prices + calculated option chains
- **Easy Integration**: Drop-in replacement for Schwab API calls
- **Minimal Patterns**: Only 3 simple patterns instead of complex architecture

This keeps the backtesting framework simple while providing all the functionality needed to test strategies against historical data.