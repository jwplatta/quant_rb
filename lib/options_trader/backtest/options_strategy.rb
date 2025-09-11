module OptionsTrader
  module Backtest
    class OptionsStrategy
      class << self
        def run(
          underlying_symbol:,
          start_date:,
          end_date:,
          underlying_price_history:,
          # strategy parameters
          strategy_type:,
          put_call: nil,
          quantity: 1,
          days_to_expiration: 30,
          short_delta: 0.05,
          max_spread: 10.0,
          min_credit: 100.0,
          min_open_interest: 0,
          increment: 0.01,
          strike_step_size: 1,
          pricing_model: OptionsTrader::Constants::COX_ROSS_RUBINSTEIN,
          # trade params
          profit_target: 0.5, # as a multiple of the credit received
          loss_threshold: 2.0, # as a multiple of the credit received
          verbose: false
        )
          backtest_iterator = HistoricalSnapshotIterator.new(
            underlying_price_history,
            OptionsTrader::Services::HistoricalOptionsChainSnapshot,
            strike_range: strike_range(underlying_price_history, strike_step_size),
            pricing_model: pricing_model
          )

          new(
            underlying_symbol: underlying_symbol,
            start_date: start_date,
            end_date: end_date,
            underlying_price_history: underlying_price_history,
            strategy_type: strategy_type,
            put_call: put_call,
            quantity: quantity,
            days_to_expiration: days_to_expiration,
            short_delta: short_delta,
            max_spread: max_spread,
            min_credit: min_credit,
            min_open_interest: min_open_interest,
            increment: increment,
            backtest_iterator: backtest_iterator,
            profit_target: profit_target,
            loss_threshold: loss_threshold,
            verbose: verbose
          ).run
        end

        def strike_range(underlying_price_history, strike_step_size)
          spot_prices = underlying_price_history.map { |candle| candle.close }
          avg_price = spot_prices.sum.to_f / spot_prices.size

          # TODO: parameterize the range size
          min_price = ((avg_price * 0.35) / 100).round * 100
          max_price = ((avg_price * 1.35) / 100).round * 100

          (min_price..max_price).step(strike_step_size).to_a
        end
      end

      def initialize(
        underlying_symbol:,
        start_date:,
        end_date:,
        strategy_type:,
        put_call:,
        quantity:,
        days_to_expiration:,
        short_delta:,
        max_spread:,
        min_credit:,
        min_open_interest:,
        increment:,
        backtest_iterator:,
        profit_target:,
        loss_threshold:,
        verbose: false
      )
        @backtest_iterator = backtest_iterator
        @portfolio = Portfolio.new(initial_balance: 100_000)
        @trade = nil
        @results = []
        @underlying_symbol = underlying_symbol
        @start_date = start_date
        @end_date = end_date
        @strategy_type = strategy_type
        @put_call = put_call
        @quantity = quantity
        @days_to_expiration = days_to_expiration
        @short_delta = short_delta
        @max_spread = max_spread
        @min_credit = min_credit
        @min_open_interest = min_open_interest
        @increment = increment
        @profit_target = profit_target
        @loss_threshold = loss_threshold
        @verbose = verbose
      end

      def run
        @backtest_iterator.each_with_index do |market_snapshot_service, index|
          if trade.nil?
            find_strategy(market_snapshot_service)
          else
            check_trade_progress(trade)
          end
        end

        generate_backtest_report
      end

      private

      def generate_backtest_report
        # TODO:
      end

      def check_trade_progress(trade)
        # TODO:
        # check the current price of the trade
        # if profit target reached, then exit and set trade = nil
        # if loss threshold reached, then exit and set trade = nil
      end

      def find_strategy(market_snapshot_service)
        strategy = StrategySearchFactory.find(
          markets_service: market_snapshot_service, #NOTE: same API as the markets service
          strategy_type: @strategy_type,
          underlying_symbol: @underlying_symbol,
          expiration_date: ensure_weekday(@days_to_expiration.days.from_now(market_snapshot_service.datetime)),
          put_call: @put_call,
          quantity: @quantity,
          short_delta: @short_delta,
          max_spread: @max_spread,
          min_credit: @min_credit,
          increment: @increment
        )

        if strategy && !strategy.is_a?(NullStrategy)
          @portfolio.enter_trade(strategy)
          @results << create_result_entry(strategy, market_snapshot_service)
        end
      end

      def ensure_weekday(date)
        case date.wday
        when 0 # Sunday
          date + 1
        when 6 # Saturday
          date + 2
        else
          date
        end
      end
    end
  end
end
