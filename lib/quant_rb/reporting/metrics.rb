# frozen_string_literal: true

module QuantRb
  module Reporting
    # Computes aggregate statistics from an array of TradeRecord objects.
    class Metrics
      attr_reader :trades

      def initialize(trades)
        @trades = Array(trades)
      end

      def total_trades
        trades.size
      end

      def winners
        trades.select(&:winner?)
      end

      def losers
        trades.reject(&:winner?)
      end

      def win_rate
        return 0.0 if total_trades.zero?
        (winners.size / total_trades.to_f * 100).round(2)
      end

      def total_pnl
        trades.sum(&:pnl)
      end

      def avg_pnl
        return 0.0 if total_trades.zero?
        total_pnl / total_trades
      end

      def avg_winner
        return 0.0 if winners.empty?
        winners.sum(&:pnl) / winners.size
      end

      def avg_loser
        return 0.0 if losers.empty?
        losers.sum(&:pnl) / losers.size
      end

      def gross_profit
        winners.sum(&:pnl)
      end

      def gross_loss
        losers.sum(&:pnl).abs
      end

      def profit_factor
        return Float::INFINITY if gross_loss.zero? && gross_profit > 0
        return 0.0 if gross_profit.zero?
        (gross_profit / gross_loss).round(4)
      end

      def max_drawdown
        return 0.0 if trades.empty?

        peak = 0.0
        max_dd = 0.0
        cumulative = 0.0

        trades.each do |t|
          cumulative += t.pnl
          peak = cumulative if cumulative > peak
          drawdown = peak - cumulative
          max_dd = drawdown if drawdown > max_dd
        end

        max_dd
      end

      def to_h
        {
          total_trades:   total_trades,
          win_rate:       win_rate,
          total_pnl:      total_pnl.round(2),
          avg_pnl:        avg_pnl.round(2),
          avg_winner:     avg_winner.round(2),
          avg_loser:      avg_loser.round(2),
          profit_factor:  profit_factor,
          max_drawdown:   max_drawdown.round(2)
        }
      end
    end
  end
end
