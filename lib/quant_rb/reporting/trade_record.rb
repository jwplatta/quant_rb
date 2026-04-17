# frozen_string_literal: true

module QuantRb
  module Reporting
    # Immutable record of a completed trade.
    class TradeRecord
      attr_reader :id, :strategy_class, :symbol, :direction, :quantity,
                  :entry_price, :exit_price, :entry_time, :exit_time,
                  :legs, :notes, :entry_fees, :entry_commissions,
                  :exit_fees, :exit_commissions

      def initialize(
        id:, strategy_class:, symbol:, direction:, quantity:,
        entry_price:, exit_price:, entry_time:, exit_time:,
        legs: [], notes: nil, entry_fees: 0.0, entry_commissions: 0.0,
        exit_fees: 0.0, exit_commissions: 0.0
      )
        @id             = id
        @strategy_class = strategy_class
        @symbol         = symbol
        @direction      = direction
        @quantity       = quantity
        @entry_price    = entry_price
        @exit_price     = exit_price
        @entry_time     = entry_time
        @exit_time      = exit_time
        @legs           = legs
        @notes          = notes
        @entry_fees = entry_fees.to_f
        @entry_commissions = entry_commissions.to_f
        @exit_fees = exit_fees.to_f
        @exit_commissions = exit_commissions.to_f
      end

      # Credit and short trades profit when the exit price is lower than the entry.
      def gross_pnl
        multiplier = multi_leg? ? 100 : 1
        delta =
          case direction
          when :credit, :short, :sell
            entry_price - exit_price
          else
            exit_price - entry_price
          end

        (delta * quantity * multiplier).round(4)
      end

      def total_fees
        entry_fees + exit_fees
      end

      def total_commissions
        entry_commissions + exit_commissions
      end

      def total_transaction_costs
        total_fees + total_commissions
      end

      def pnl
        (gross_pnl - total_transaction_costs).round(4)
      end

      def winner?
        pnl > 0
      end

      def duration_minutes
        return nil unless entry_time && exit_time
        ((exit_time - entry_time) / 60.0).round
      end

      def multi_leg?
        legs.size > 1
      end

      def to_h
        {
          id:             id,
          strategy_class: strategy_class.to_s,
          symbol:         symbol,
          direction:      direction,
          quantity:       quantity,
          entry_price:    entry_price,
          exit_price:     exit_price,
          entry_time:     entry_time,
          exit_time:      exit_time,
          gross_pnl:      gross_pnl,
          pnl:            pnl,
          winner:         winner?,
          duration_min:   duration_minutes,
          entry_fees:     entry_fees,
          entry_commissions: entry_commissions,
          exit_fees:      exit_fees,
          exit_commissions: exit_commissions,
          total_transaction_costs: total_transaction_costs,
          legs:           legs,
          notes:          notes
        }
      end
    end
  end
end
