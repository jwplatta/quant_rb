# frozen_string_literal: true

module QuantRb
  module Reality
    # Fills single-leg orders at the last close and option combos at midpoint.
    class OptimisticFillModel < FillModel
      def simulate_fill(order, slice)
        price =
          if order.market_order?
            simulate_market_fill(order, slice)
          else
            simulate_combo_fill(order, slice)
          end

        price&.round(4)
      end

      private

      def simulate_market_fill(order, slice)
        leg = order.legs.first
        candle = find_candle(slice, leg[:symbol])
        candle&.close&.to_f
      end

      def simulate_combo_fill(order, slice)
        net = 0.0
        order.legs.each do |leg|
          opt = find_option(slice, leg[:symbol])
          return nil unless opt

          price = leg_fill_price(opt, leg[:quantity])
          return nil unless price

          net -= price.to_f * leg[:quantity].to_i
        end

        net
      end

      def leg_fill_price(opt, _quantity)
        opt.mid || opt.mark
      end

      def find_option(slice, symbol)
        slice.option_chains.each_value do |chains_by_expiry|
          chains_by_expiry.each_value do |chain|
            opt = chain.all_options.find { |option| option.symbol == symbol }
            return opt if opt
          end
        end
        nil
      end

      def find_candle(slice, symbol_key)
        slice.bars[symbol_key.to_sym] || slice.bars[symbol_key.to_s]
      end
    end
  end
end
