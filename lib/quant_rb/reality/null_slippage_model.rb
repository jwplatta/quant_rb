# frozen_string_literal: true

module QuantRb
  module Reality
    # Models zero slippage.
    class NullSlippageModel < SlippageModel
      def adjust_price(base_price, order:, slice: nil)
        base_price.to_f
      end
    end
  end
end
