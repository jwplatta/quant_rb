# frozen_string_literal: true

module QuantRb
  module Reality
    CostBreakdown = Struct.new(:fees, :commissions, keyword_init: true) do
      def initialize(fees: 0.0, commissions: 0.0)
        super(fees: fees.to_f, commissions: commissions.to_f)
      end

      def total
        fees + commissions
      end
    end
  end
end
