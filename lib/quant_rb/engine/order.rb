# frozen_string_literal: true

require "securerandom"

module QuantRb
  module Engine
    # Value object representing a submitted order.
    #
    # legs:        Array of { symbol: String, quantity: Integer }  (negative qty = short)
    # quantity:    Number of spreads / contracts
    # limit_price: Per-contract limit price (nil for market orders)
    # direction:   :credit, :debit, :buy, :sell
    # submitted_at: Time the order was submitted
    #
    Order = Struct.new(
      :id, :legs, :quantity, :limit_price, :direction, :submitted_at,
      keyword_init: true
    ) do
      def initialize(legs:, quantity:, direction:, limit_price: nil, submitted_at: nil, id: nil)
        super(
          id:           id || SecureRandom.uuid,
          legs:         legs,
          quantity:     quantity,
          limit_price:  limit_price,
          direction:    direction,
          submitted_at: submitted_at
        )
      end

      def market_order?
        limit_price.nil?
      end

      def credit?
        direction == :credit
      end

      def debit?
        direction == :debit
      end

      def multi_leg?
        legs.size > 1
      end

      def symbol
        legs.first[:symbol]
      end

      def signed_quantity
        legs.sum { |leg| leg[:quantity].to_i }
      end

      def option_order?
        multi_leg?
      end
    end

    # Returned by broker#submit_order.
    OrderTicket = Struct.new(:order_id, :status, keyword_init: true)
  end
end
