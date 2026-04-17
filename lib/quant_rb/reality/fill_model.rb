# frozen_string_literal: true

module QuantRb
  module Reality
    # Base interface for fill-price simulation models.
    class FillModel
      def simulate_fill(order, slice)
        raise NotImplementedError, "#{self.class} must implement #simulate_fill"
      end
    end
  end
end
