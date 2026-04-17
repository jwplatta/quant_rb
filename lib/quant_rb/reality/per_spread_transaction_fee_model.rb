# frozen_string_literal: true

module QuantRb
  module Reality
    # Applies fixed fees and commissions per spread unit.
    class PerSpreadTransactionFeeModel < TransactionFeeModel
      def initialize(option_fee_per_spread: 0.0, option_commission_per_spread: 0.0)
        @option_fee_per_spread = option_fee_per_spread.to_f
        @option_commission_per_spread = option_commission_per_spread.to_f
      end

      def estimate(order, fill_price: nil, slice: nil)
        return CostBreakdown.new unless order.multi_leg?

        spread_units = spread_count(order)
        CostBreakdown.new(
          fees: spread_units * @option_fee_per_spread,
          commissions: spread_units * @option_commission_per_spread
        )
      end

      private

      def spread_count(order)
        spreads_per_contract = [order.legs.size / 2, 1].max
        spreads_per_contract * order.quantity.to_i.abs
      end
    end
  end
end
