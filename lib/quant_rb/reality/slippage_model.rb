# frozen_string_literal: true

module QuantRb
  module Reality
    # Base interface for slippage models.
    class SlippageModel
      def adjust_price(base_price, order:, slice: nil)
        raise NotImplementedError, "#{self.class} must implement #adjust_price"
      end
    end
  end
end
