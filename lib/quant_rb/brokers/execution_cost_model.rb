# frozen_string_literal: true

module QuantRb
  module Brokers
    # Computes transaction costs applied by the backtest broker when orders fill.
    class ExecutionCostModel
      CostBreakdown = Struct.new(:fees, :commissions, keyword_init: true) do
        def total
          fees.to_f + commissions.to_f
        end
      end

      def self.none
        new
      end

      def self.schwab_spxw_options
        new(option_fee_per_spread: 1.14, option_commission_per_spread: 1.30)
      end

      def initialize(option_fee_per_spread: 0.0, option_commission_per_spread: 0.0)
        @option_fee_per_spread = option_fee_per_spread.to_f
        @option_commission_per_spread = option_commission_per_spread.to_f
      end

      def estimate(order)
        return CostBreakdown.new(fees: 0.0, commissions: 0.0) unless order.multi_leg?

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
