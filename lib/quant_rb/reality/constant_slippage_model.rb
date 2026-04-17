# frozen_string_literal: true

module QuantRb
  module Reality
    # Applies a constant adverse price move to each simulated fill.
    class ConstantSlippageModel < SlippageModel
      def initialize(amount:)
        @amount = amount.to_f
      end

      def adjust_price(base_price, order:, slice: nil)
        return base_price.to_f if @amount.zero?

        base_price.to_f + adverse_move_for(order)
      end

      private

      def adverse_move_for(order)
        case order.direction
        when :credit, :sell
          -@amount
        when :debit, :buy
          @amount
        else
          0.0
        end
      end
    end
  end
end
