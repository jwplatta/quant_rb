# frozen_string_literal: true

module QuantRb
  module Engine
    # Drives the backtesting loop. Iterates over candle time steps, builds slices,
    # fires scheduled callbacks, and dispatches event hooks to the strategy.
    #
    # TODO (Phase 4): Continue tightening the real data-layer integration.
    #                 Current implementation still supports injected data sources for tests.
    #
    class BacktestEngine
      # Run a backtest for the given strategy class.
      # Returns a QuantRb::Reporting::BacktestResult.
      def self.run(strategy_class, broker: nil, candle_series: nil, options_chain_index: nil, progress: :auto)
        new(
          strategy_class:       strategy_class,
          broker:               broker,
          candle_series:        candle_series,
          options_chain_index:  options_chain_index,
          progress:             progress
        ).run
      end

      def initialize(strategy_class:, broker: nil, candle_series: nil, options_chain_index: nil, progress: :auto)
        @strategy_class      = strategy_class
        @broker              = broker
        @candle_series       = candle_series
        @options_chain_index = options_chain_index
        @progress            = progress
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
        strategy.subscribed_underlyings.each do |key, sub|
          securities.register(key, sub)
        end

        registry = resolve_registry
        candle_series_map = resolve_candle_series_map(strategy, registry)
        option_chain_indexes = resolve_option_chain_index_map(strategy, registry)
        primary_key = strategy.subscribed_underlyings.keys.first
        raise ArgumentError, "BacktestEngine requires at least one candle subscription" unless primary_key

        primary_series = candle_series_map.fetch(primary_key)
        candles = primary_series.to_a
        progress_reporter = Reporting::ProgressReporter.new(
          total: candles.size,
          title: strategy.class.name || "Backtest",
          enabled: @progress
        )

        candles.each_with_index do |candle, idx|
          current_time = candle.datetime
          strategy.send(:set_time, current_time)

          bars = build_bars(current_time, candle_series_map)
          bars.each do |symbol_key, bar|
            securities.update(symbol_key, bar)
          end

          # Fire scheduled callbacks
          scheduler.fire(current_time)

          chains = build_option_chains(current_time, strategy, option_chain_indexes)
          slice = Slice.new(time: current_time, bars: bars, option_chains: chains)

          # Dispatch on_data
          strategy.on_data(slice)

          # Simulate fills
          broker.process_pending_orders(slice, portfolio)

          # End-of-day callbacks
          current_date = current_time.to_date
          next_date    = candles[idx + 1]&.datetime&.to_date
          if next_date != current_date
            broker.cancel_all_pending_orders(reason: :end_of_day) if broker.respond_to?(:cancel_all_pending_orders)
            broker.process_expirations(slice, portfolio, strategy_class: strategy.class) if broker.respond_to?(:process_expirations)
            strategy.subscribed_symbols.each { |sym| strategy.on_end_of_day(sym) }
          end

          progress_reporter.increment
        end

        progress_reporter.finish
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

      private

      def resolve_registry
        return nil if @candle_series && @options_chain_index

        QuantRb::Data::DataSourcesRegistry.load
      end

      def resolve_candle_series_map(strategy, registry)
        subscriptions = strategy.subscribed_underlyings
        raise ArgumentError, "BacktestEngine requires at least one candle subscription" if subscriptions.empty?

        explicit_series_map(@candle_series, subscriptions.keys) || load_candle_series_map(strategy, registry)
      end

      def resolve_option_chain_index_map(strategy, registry)
        subscriptions = strategy.subscribed_option_chains
        return {} if subscriptions.empty?

        explicit_series_map(@options_chain_index, subscriptions.keys) || load_option_chain_index_map(strategy, registry)
      end

      def explicit_series_map(explicit_value, keys)
        return nil if explicit_value.nil?
        return explicit_value.transform_keys(&:to_sym) if explicit_value.is_a?(Hash)
        return { keys.first => explicit_value } if keys.size == 1

        raise ArgumentError, "Multiple subscriptions require a hash of injected data sources"
      end

      def load_candle_series_map(strategy, registry)
        adapter = build_tickrake_adapter(registry)

        strategy.subscribed_underlyings.each_with_object({}) do |(key, subscription), result|
          resolved = registry.resolve_underlying(subscription)
          series = adapter.load_candle_series(
            provider: resolved.fetch(:provider),
            ticker: resolved.fetch(:symbol),
            resolution: resolved.fetch(:resolution, :minute),
            start_date: strategy.start_date,
            end_date: strategy.end_date,
            timezone: strategy.market_timezone
          )
          raise QuantRb::Error, "No candle data for #{resolved.fetch(:symbol)} via provider #{resolved.fetch(:provider)} for #{strategy.start_date}..#{strategy.end_date}" if series.to_a.empty?

          result[key] = series
        end
      end

      def load_option_chain_index_map(strategy, registry)
        adapter = build_tickrake_adapter(registry)

        strategy.subscribed_option_chains.each_with_object({}) do |(key, subscription), result|
          resolved = registry.resolve_option_chain(subscription)
          source = QuantRb::Data::OptionChainSource.build(
            config: resolved.config,
            start_date: strategy.start_date,
            end_date: strategy.end_date,
            adapter: adapter
          )
          source.preload! if source.respond_to?(:preload!)
          if !resolved.config.synthetic? && source.respond_to?(:available_dates) && source.available_dates.empty?
            raise QuantRb::Error,
                  "No option chain data for #{resolved.subscription.fetch(:option_root)} via provider #{resolved.subscription.fetch(:provider)} for #{strategy.start_date}..#{strategy.end_date}"
          end
          result[key] = source
        end
      end

      def build_tickrake_adapter(registry)
        QuantRb::Data::Adapters::TickrakeAdapter.new(config_path: registry.tickrake_config_path)
      end

      def build_bars(current_time, candle_series_map)
        candle_series_map.each_with_object({}) do |(key, series), bars|
          candle = series.at(current_time)
          bars[key] = candle if candle
        end
      end

      def build_option_chains(current_time, strategy, option_chain_indexes)
        strategy.subscribed_option_chains.each_with_object({}) do |(key, subscription), chains|
          index = option_chain_indexes[key]
          next unless index

          chains[key] = index.chains_at(current_time, expiry_filter: subscription[:filter])
        end
      end
    end
  end
end
