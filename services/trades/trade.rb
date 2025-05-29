# frozen_string_literal: true

require_relative '../../mixins/schwab/schwab'
require_relative '../../mixins/orderable'
require_relative '../../mixins/quoteable'
require_relative '../../mixins/position_progress'

Order = Struct.new(:id, :status, :date)

module Services
  module Trades
    class Trade
      include Orderable
      include Quoteable
      include PositionProgress

      attr_accessor :increment, :round, :exit_threshold, :max_loss, :quantity,
                    :underlying_symbol

      def initialize(underlying_symbol: nil, increment: 0.01, round: 2, quantity: 1)
        @underlying_symbol = underlying_symbol
        @increment = increment
        @round = round
        @quantity = quantity

        initialize_orderable
        init_progress
      end

      def net_filled_open_credit_debit
        filled_open_credit_debit.to_f * 100 - filled_open_fees.to_f - filled_open_commission.to_f
      end

      def nearest_increment(value)
        (value / increment).floor * increment
      end

      def to_json(*_args)
        to_h.to_json
      end
    end
  end
end
