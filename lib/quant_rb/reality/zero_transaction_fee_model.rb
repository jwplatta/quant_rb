# frozen_string_literal: true

module QuantRb
  module Reality
    # Models zero fees and commissions.
    class ZeroTransactionFeeModel < TransactionFeeModel
      def estimate(order, fill_price: nil, slice: nil)
        CostBreakdown.new
      end
    end
  end
end
