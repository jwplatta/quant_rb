# frozen_string_literal: true

module QuantRb
  module Engine
    # Drives the backtesting loop. Iterates over candle time steps, builds slices,
    # fires scheduled callbacks, and dispatches event hooks to the strategy.
    #
    # TODO (Phase 4): Wire in real Data layer (CandleLoader, OptionsChainIndex).
    #                 Current implementation is a skeleton with stub data sources.
    #
    class BacktestEngine
      # Run a backtest for the given strategy class.
      # Returns a QuantRb::Reporting::BacktestResult.
      def self.run(strategy_class, broker: nil, candle_series: nil, options_chain_index: nil)
        new(
          strategy_class:       strategy_class,
          broker:               broker,
          candle_series:        candle_series,
          options_chain_index:  options_chain_index
        ).run
      end

      def initialize(strategy_class:, broker: nil, candle_series: nil, options_chain_index: nil)
        @strategy_class      = strategy_class
        @broker              = broker
        @candle_series       = candle_series
        @options_chain_index = options_chain_index
      end

      def run
        portfolio = Portfolio.new(initial_cash: 100_000)  # default; overridden by strategy.set_cash
        scheduler = Scheduler.new
        securities = Securities.new

        broker = @broker || Brokers::BacktestBroker.new

        strategy = @strategy_class.build_for_engine(
          portfolio: portfolio,
          schedule: scheduler,
          securities: securities,
          broker: broker
        )

        portfolio = Portfolio.new(initial_cash: strategy.initial_cash || 100_000)
        strategy.send(:set_portfolio, portfolio)

        # Register subscriptions with securities registry
        strategy.subscribed_candle_symbols.each do |key, sub|
          securities.register(key, sub)
        end

        # TODO (Phase 4): Load real candle data and options chain index here:
        # candle_series = @candle_series || load_candle_series(strategy)
        # options_chain_index = @options_chain_index || load_options_chain_index(strategy)

        candles = @candle_series&.to_a || []
        prev_date = nil

        candles.each_with_index do |candle, idx|
          current_time = candle.datetime
          strategy.send(:set_time, current_time)

          # Update securities registry
          primary_key = strategy.subscribed_candle_symbols.keys.first
          securities.update(primary_key, candle) if primary_key

          # Fire scheduled callbacks
          scheduler.fire(current_time)

          # Build slice
          bars = primary_key ? { primary_key => candle } : {}
          chains = {}
          if @options_chain_index
            strategy.subscribed_option_chain_symbols.each do |key, _sub|
              chains[key] = @options_chain_index.chains_at(current_time)
            end
          end
          slice = Slice.new(time: current_time, bars: bars, option_chains: chains)

          # Dispatch on_data
          strategy.on_data(slice)

          # Simulate fills
          broker.process_pending_orders(slice, portfolio)

          # End-of-day callbacks
          current_date = current_time.to_date
          next_date    = candles[idx + 1]&.datetime&.to_date
          if next_date != current_date && prev_date != current_date
            strategy.subscribed_symbols.each { |sym| strategy.on_end_of_day(sym) }
          end

          prev_date = current_date
        end

        strategy.on_end_of_algorithm

        Reporting::BacktestResult.new(
          strategy_class:        @strategy_class,
          start_date:            strategy.start_date,
          end_date:              strategy.end_date,
          initial_cash:          strategy.initial_cash || 100_000,
          final_portfolio_value: portfolio.total_value,
          trades:                portfolio.trade_history
        )
      end
    end
  end
end
