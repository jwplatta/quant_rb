# frozen_string_literal: true

module QuantRb
  module Reporting
    # Container returned by BacktestEngine.run.
    class BacktestResult
      attr_reader :strategy_class, :start_date, :end_date,
                  :initial_cash, :final_portfolio_value, :trades

      def initialize(strategy_class:, start_date:, end_date:,
                     initial_cash:, final_portfolio_value:, trades: [])
        @strategy_class        = strategy_class
        @start_date            = start_date
        @end_date              = end_date
        @initial_cash          = initial_cash
        @final_portfolio_value = final_portfolio_value
        @trades                = Array(trades)
      end

      def metrics
        @metrics ||= Metrics.new(trades)
      end

      def total_return
        return 0.0 if initial_cash.zero?
        ((final_portfolio_value - initial_cash) / initial_cash.to_f * 100).round(2)
      end

      def summary
        m = metrics.to_h
        lines = [
          "=" * 50,
          "Backtest: #{strategy_class}",
          "Period:   #{start_date} → #{end_date}",
          "-" * 50,
          "Initial cash:     $#{"%.2f" % initial_cash}",
          "Final value:      $#{"%.2f" % final_portfolio_value}",
          "Total return:     #{total_return}%",
          "-" * 50,
          "Total trades:     #{m[:total_trades]}",
          "Win rate:         #{m[:win_rate]}%",
          "Total P&L:        $#{"%.2f" % m[:total_pnl]}",
          "Avg P&L/trade:    $#{"%.2f" % m[:avg_pnl]}",
          "Avg winner:       $#{"%.2f" % m[:avg_winner]}",
          "Avg loser:        $#{"%.2f" % m[:avg_loser]}",
          "Profit factor:    #{m[:profit_factor]}",
          "Max drawdown:     $#{"%.2f" % m[:max_drawdown]}",
          "Sharpe ratio:     #{m[:sharpe_ratio]}",
          "=" * 50
        ]
        lines.join("\n")
      end

      def to_h
        {
          strategy_class: strategy_class.to_s,
          start_date: start_date,
          end_date: end_date,
          initial_cash: initial_cash,
          final_portfolio_value: final_portfolio_value,
          total_return: total_return,
          trades: trades.map(&:to_h),
          metrics: metrics.to_h
        }
      end
    end
  end
end
