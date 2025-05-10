# frozen_string_literal: true

require_relative '../../mixins/schwab/schwab'
require_relative '../../mixins/orderable'

Order = Struct.new(:id, :status, :date)

module Services
  module Trades
    class Trade
      include Orderable

      attr_accessor :increment, :round, :exit_threshold, :max_loss, :quantity,
                    :underlying_symbol

      def initialize(
        underlying_symbol: nil, increment: 0.01,
        round: 2, exit_threshold: 0.75, max_loss: -3.0, quantity: 1
      )
        @underlying_symbol = underlying_symbol
        @increment = increment
        @round = round
        @exit_threshold = exit_threshold
        @max_loss = max_loss
        @quantity = quantity
        initialize_orderable
      end

      def credit_debit
        raise 'Must be implemented in subclass'
      end

      def net_credit_debit
        raise 'Must be implemented in subclass'
      end

      def delta
        raise 'Must be implemented in subclass'
      end

      def check_market
        raise 'Must be implemented in subclass'
      end

      def exitable?
        progress >= exit_threshold || progress <= max_loss
      end

      def progress
        return nil unless filled_open_credit_debit

        (net_credit_debit - net_filled_open_credit_debit) / net_filled_open_credit_debit
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
