# frozen_string_literal: true

module QuantRb
  module Reality
    # Base interface for transaction fee and commission models.
    class TransactionFeeModel
      def estimate(order, fill_price: nil, slice: nil)
        raise NotImplementedError, "#{self.class} must implement #estimate"
      end
    end
  end
end
