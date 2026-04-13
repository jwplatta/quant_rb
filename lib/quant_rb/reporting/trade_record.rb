# frozen_string_literal: true

module QuantRb
  module Reporting
    # Immutable record of a completed trade.
    class TradeRecord
      attr_reader :id, :strategy_class, :symbol, :direction, :quantity,
                  :entry_price, :exit_price, :entry_time, :exit_time,
                  :legs, :notes

      def initialize(
        id:, strategy_class:, symbol:, direction:, quantity:,
        entry_price:, exit_price:, entry_time:, exit_time:,
        legs: [], notes: nil
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
      end

      # Credit and short trades profit when the exit price is lower than the entry.
      def pnl
        multiplier = multi_leg? ? 100 : 1
        delta =
          case direction
          when :credit, :short, :sell
            entry_price - exit_price
          else
            exit_price - entry_price
          end

        delta * quantity * multiplier
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
          pnl:            pnl,
          winner:         winner?,
          duration_min:   duration_minutes,
          legs:           legs,
          notes:          notes
        }
      end
    end
  end
end
