module OptionsTrader
  module Backtest
    class OptionsStrategy
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
  end
end
