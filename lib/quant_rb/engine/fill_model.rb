# frozen_string_literal: true

module QuantRb
  module Engine
    # Simulates order fills for backtesting.
    #
    # model:    :mid (fill at midpoint), :bid_ask (conservative: sell at bid, buy at ask)
    # slippage: additional per-contract cost applied to fills
    #
    # TODO (Phase 3): Implement full fill simulation using slice data.
    #
    class FillModel
      MODELS = %i[mid bid_ask worst_case].freeze

      def initialize(model: :bid_ask, slippage: 0.0)
        raise ArgumentError, "Unknown fill model: #{model}" unless MODELS.include?(model)

        @model    = model
        @slippage = slippage
      end

      # Returns simulated net credit/debit for a multi-leg order given current slice data.
      # Returns nil if any leg's option data is missing.
      def simulate_fill(order, slice)
        return simulate_market_fill(order, slice) if order.market_order?

        simulate_combo_fill(order, slice)
      end

      private

      def simulate_market_fill(order, slice)
        leg = order.legs.first
        candle = find_candle(slice, leg[:symbol])
        return nil unless candle

        candle.close
      end

      def simulate_combo_fill(order, slice)
        net = 0.0
        order.legs.each do |leg|
          opt = find_option(slice, leg[:symbol])
          return nil unless opt

          price = leg_fill_price(opt, leg[:quantity])
          net  += price * leg[:quantity] + @slippage
        end
        net
      end

      def leg_fill_price(opt, quantity)
        case @model
        when :mid
          opt.mid || opt.mark
        when :bid_ask
          quantity.negative? ? (opt.bid || opt.mark) : (opt.ask || opt.mark)
        when :worst_case
          quantity.negative? ? (opt.bid || opt.mark) : (opt.ask || opt.mark)
        end
      end

      def find_option(slice, symbol)
        slice.option_chains.each_value do |chains_by_expiry|
          chains_by_expiry.each_value do |chain|
            opt = chain.all_options.find { |o| o.symbol == symbol }
            return opt if opt
          end
        end
        nil
      end

      def find_candle(slice, symbol_key)
        slice.bars[symbol_key.to_sym]
      end
    end
  end
end
