# frozen_string_literal: true

module QuantRb
  module Engine
    # Base class for all user-defined strategies. Mirrors QCAlgorithm's lifecycle.
    #
    # Users inherit from QuantRb::Strategy (aliased below) and override event hooks:
    #
    #   class MyStrategy < QuantRb::Strategy
    #     def initialize
    #       set_start_date(2024, 1, 1)
    #       set_end_date(2024, 12, 31)
    #       set_cash(100_000)
    #       @spy = add_equity("SPY", resolution: :minute)
    #       schedule.on(date_rules.every_day(@spy), time_rules.at(15, 0), method(:check_entry))
    #     end
    #
    #     def on_data(slice); end
    #     def on_end_of_day(symbol); end
    #     def on_end_of_algorithm; end
    #   end
    #
    class StrategyBase
      def self.build_for_engine(portfolio:, schedule:, securities:, broker:)
        instance = allocate
        instance.send(:set_portfolio, portfolio)
        instance.send(:set_schedule, schedule)
        instance.send(:set_securities, securities)
        instance.send(:set_broker, broker)
        instance.send(:initialize)
        instance
      end

      # Injected by the engine before initialize is called
      attr_reader :time, :portfolio, :securities, :schedule, :broker

      # TODO (Phase 3): Implement full engine wiring
      # - set_start_date / set_end_date / set_cash store config for BacktestEngine
      # - add_equity / add_index / add_index_option register subscriptions
      # - schedule exposes Scheduler instance
      # - combo_limit_order / market_order delegate to b

      # ── Configuration helpers (called inside user's initialize) ───────────

      def set_start_date(year, month, day)
        @start_date = Date.new(year, month, day)
      end

      def set_end_date(year, month, day)
        @end_date = Date.new(year, month, day)
      end

      def set_cash(amount)
        @initial_cash = amount
      end

      # ── Symbol subscriptions ──────────────────────────────────────────────

      # Register an equity symbol. Returns a symbol key used to access data in slices.
      def add_equity(symbol, resolution: :minute, provider: nil)
        key = symbol.to_sym
        subscriptions[:candles][key] = { symbol: symbol, resolution: resolution, type: :equity, provider: provider }
        key
      end

      # Register an index symbol.
      def add_index(symbol, resolution: :minute, provider: nil)
        key = symbol.to_sym
        subscriptions[:candles][key] = { symbol: symbol, resolution: resolution, type: :index, provider: provider }
        key
      end

      # Register an options chain subscription for an underlying.
      # Optionally pass a block to configure expiry/strike filters.
      def add_index_option(underlying, option_root, resolution: :minute, provider: nil, synthetic: false, interpolate: false, pricing_model: :black_scholes, iv: nil, validation: :repair, strike_grid: {}, **kwargs, &filter)
        key = :"#{option_root}_options"
        chain_mode =
          if synthetic
            :synthetic
          elsif interpolate
            :sampled_interpolated
          else
            :sampled_validated
          end
        subscriptions[:option_chains][key] = {
          underlying: underlying,
          option_root: option_root,
          resolution: resolution,
          provider: provider,
          filter: filter,
          config: QuantRb::Data::OptionChainConfig.new(
            underlying: underlying,
            option_root: option_root,
            resolution: resolution,
            provider: provider,
            chain_mode: chain_mode,
            pricing_model: pricing_model,
            iv_map: iv,
            validation: validation,
            strike_grid: strike_grid,
            raw_options: kwargs
          )
        }
        key
      end

      # ── Scheduling ────────────────────────────────────────────────────────

      def date_rules
        @date_rules ||= QuantRb::Engine::DateRules.new
      end

      def time_rules
        @time_rules ||= QuantRb::Engine::TimeRules.new
      end

      # ── Order placement ───────────────────────────────────────────────────

      # Place a multi-leg combo limit order. Returns an OrderTicket.
      # legs: Array of { symbol: String, quantity: Integer } (negative = short)
      def combo_limit_order(legs, quantity, limit_price)
        raise "No broker configured" unless broker

        order = QuantRb::Engine::Order.new(
          legs: legs,
          quantity: quantity,
          limit_price: limit_price.abs,
          direction: limit_price >= 0 ? :credit : :debit,
          submitted_at: time
        )
        broker.submit_order(order)
      end

      # Place a simple market order for equities/indexes.
      def market_order(symbol, quantity)
        raise "No broker configured" unless broker

        order = QuantRb::Engine::Order.new(
          legs: [{ symbol: symbol, quantity: quantity }],
          quantity: quantity.abs,
          limit_price: nil,
          direction: quantity >= 0 ? :buy : :sell,
          submitted_at: time
        )
        broker.submit_order(order)
      end

      # ── Event hooks (users override these) ────────────────────────────────

      def on_data(slice); end
      def on_end_of_day(symbol); end
      def on_end_of_algorithm; end

      # ── Logging ───────────────────────────────────────────────────────────

      def log(msg)
        info(msg)
      end

      def debug(msg)
        logger.debug(format_log_message(msg))
      end

      def info(msg)
        logger.info(format_log_message(msg))
      end

      def warn(msg)
        logger.warn(format_log_message(msg))
      end

      def error(msg)
        logger.error(format_log_message(msg))
      end

      # ── Internal accessors (used by BacktestEngine) ───────────────────────

      attr_reader :start_date, :end_date, :initial_cash

      def subscribed_candle_symbols
        subscriptions[:candles]
      end

      def subscribed_option_chain_symbols
        subscriptions[:option_chains]
      end

      def subscribed_symbols
        subscriptions[:candles].keys + subscriptions[:option_chains].keys
      end

      private

      def subscriptions
        @subscriptions ||= { candles: {}, option_chains: {} }
      end

      def logger
        QuantRb.logger
      end

      def format_log_message(msg)
        prefix = time ? "[#{time.utc}]" : "[no-time]"
        "#{prefix} #{self.class}: #{msg}"
      end

      # Engine calls these to inject dependencies
      def set_time(t);       @time = t;       end
      def set_portfolio(p);  @portfolio = p;  end
      def set_securities(s); @securities = s; end
      def set_schedule(s);   @schedule = s;   end
      def set_broker(b);     @broker = b;     end
    end
  end

  # Public alias — strategy authors write `class MyStrategy < QuantRb::Strategy`
  Strategy = Engine::StrategyBase
end
