# frozen_string_literal: true

module QuantRb
  module Engine
    # Represents a single open position in the portfolio.
    class Position
      attr_reader :id, :order, :entry_time, :legs, :direction,
                  :entry_fees, :entry_commissions
      attr_accessor :entry_price, :quantity, :current_price

      def initialize(id:, order:, quantity:, entry_price:, entry_time:, direction:, current_price: nil,
                     entry_fees: 0.0, entry_commissions: 0.0)
        @id = id
        @order = order
        @quantity = quantity
        @entry_price = entry_price.to_f
        @entry_time = entry_time
        @direction = direction
        @current_price = (current_price || entry_price).to_f
        @legs = Array(order&.legs).map(&:dup).freeze
        @entry_fees = entry_fees.to_f
        @entry_commissions = entry_commissions.to_f
      end

      def multi_leg?
        legs.size > 1
      end

      def long?
        direction == :long || direction == :debit
      end

      def short?
        direction == :short || direction == :credit
      end

      def market_value
        return 0.0 if multi_leg?

        current_price * quantity
      end

      def pnl(price = current_price)
        delta = price.to_f - entry_price
        short? ? -delta * quantity : delta * quantity
      end
    end
  end
end
