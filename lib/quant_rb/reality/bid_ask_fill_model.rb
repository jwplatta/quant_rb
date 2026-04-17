# frozen_string_literal: true

module QuantRb
  module Reality
    # Fills option legs conservatively: sells at bid, buys at ask.
    class BidAskFillModel < OptimisticFillModel
      private

      def leg_fill_price(opt, quantity)
        quantity.negative? ? (opt.bid || opt.mark || opt.mid) : (opt.ask || opt.mark || opt.mid)
      end
    end
  end
end
