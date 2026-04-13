# frozen_string_literal: true

module QuantRb
  module Engine
    # Tracks cash, open positions, and completed trades for a strategy run.
    class Portfolio
      attr_reader :cash, :positions, :trade_history, :initial_cash

      def initialize(initial_cash:)
        @initial_cash = initial_cash.to_f
        @cash = initial_cash.to_f
        @positions = {}
        @trade_history = []
      end

      def invested?
        positions.any?
      end

      def total_value
        cash + positions.values.sum(&:market_value)
      end

      def record_fill(order, fill_price, fill_time, strategy_class: nil)
        if order.multi_leg?
          record_multi_leg_fill(order, fill_price, fill_time)
        else
          record_single_leg_fill(order, fill_price, fill_time, strategy_class: strategy_class)
        end
      end

      def close_position(order_id, close_price, close_time, strategy_class: nil, notes: nil)
        position = @positions.delete(order_id)
        return unless position

        @cash += if position.multi_leg?
                   combo_close_cash_flow(position, close_price)
                 else
                   position.quantity * close_price.to_f
                 end

        trade_history << build_trade_record(
          position: position,
          close_price: close_price,
          close_time: close_time,
          strategy_class: strategy_class,
          notes: notes
        )

        position
      end

      def mark_to_market(slice)
        positions.each_value do |position|
          next if position.multi_leg?

          candle = slice.bars[position.id] || slice.bars[position.id.to_s]
          next unless candle

          position.current_price = candle.close.to_f
        end
      end

      private

      def record_multi_leg_fill(order, fill_price, fill_time)
        position = QuantRb::Engine::Position.new(
          id: order.id,
          order: order,
          quantity: order.quantity,
          entry_price: fill_price,
          entry_time: fill_time,
          direction: order.credit? ? :credit : :debit,
          current_price: fill_price
        )

        @positions[position.id] = position
        @cash += combo_open_cash_flow(order, fill_price)
      end

      def record_single_leg_fill(order, fill_price, fill_time, strategy_class:)
        symbol = order.symbol.to_sym
        signed_quantity = order.signed_quantity

        @cash -= fill_price.to_f * signed_quantity

        existing = @positions[symbol]
        unless existing
          @positions[symbol] = build_single_leg_position(symbol, order, signed_quantity, fill_price, fill_time)
          return
        end

        if same_direction?(existing.direction, signed_quantity)
          scale_position(existing, signed_quantity, fill_price)
          return
        end

        close_against_position(
          symbol: symbol,
          existing: existing,
          order: order,
          signed_quantity: signed_quantity,
          fill_price: fill_price,
          fill_time: fill_time,
          strategy_class: strategy_class
        )
      end

      def build_single_leg_position(symbol, order, signed_quantity, fill_price, fill_time)
        QuantRb::Engine::Position.new(
          id: symbol,
          order: order,
          quantity: signed_quantity.abs,
          entry_price: fill_price,
          entry_time: fill_time,
          direction: signed_quantity.positive? ? :long : :short,
          current_price: fill_price
        )
      end

      def scale_position(position, signed_quantity, fill_price)
        added_quantity = signed_quantity.abs
        total_quantity = position.quantity + added_quantity
        weighted_entry = ((position.entry_price * position.quantity) + (fill_price.to_f * added_quantity)) / total_quantity

        position.entry_price = weighted_entry
        position.quantity = total_quantity
        position.current_price = fill_price.to_f
      end

      def close_against_position(symbol:, existing:, order:, signed_quantity:, fill_price:, fill_time:, strategy_class:)
        closing_quantity = [existing.quantity, signed_quantity.abs].min

        trade_history << QuantRb::Reporting::TradeRecord.new(
          id: existing.id,
          strategy_class: strategy_class || infer_strategy_class(existing.order),
          symbol: symbol,
          direction: existing.direction,
          quantity: closing_quantity,
          entry_price: existing.entry_price,
          exit_price: fill_price.to_f,
          entry_time: existing.entry_time,
          exit_time: fill_time,
          legs: existing.legs
        )

        remaining_existing = existing.quantity - closing_quantity
        incoming_remainder = signed_quantity.abs - closing_quantity

        if remaining_existing.positive?
          existing.quantity = remaining_existing
          existing.current_price = fill_price.to_f
          return
        end

        @positions.delete(symbol)
        return unless incoming_remainder.positive?

        net_signed_quantity = signed_quantity.positive? ? incoming_remainder : -incoming_remainder
        @positions[symbol] = build_single_leg_position(symbol, order, net_signed_quantity, fill_price, fill_time)
      end

      def build_trade_record(position:, close_price:, close_time:, strategy_class:, notes:)
        QuantRb::Reporting::TradeRecord.new(
          id: position.id,
          strategy_class: strategy_class || infer_strategy_class(position.order),
          symbol: trade_symbol_for(position),
          direction: position.direction,
          quantity: position.quantity,
          entry_price: position.entry_price,
          exit_price: close_price.to_f,
          entry_time: position.entry_time,
          exit_time: close_time,
          legs: position.legs,
          notes: notes
        )
      end

      def combo_open_cash_flow(order, fill_price)
        signed_fill = order.credit? ? fill_price.to_f : -fill_price.to_f
        signed_fill * order.quantity * 100
      end

      def combo_close_cash_flow(position, close_price)
        signed_fill = position.direction == :credit ? -close_price.to_f : close_price.to_f
        signed_fill * position.quantity * 100
      end

      def same_direction?(direction, signed_quantity)
        (direction == :long && signed_quantity.positive?) || (direction == :short && signed_quantity.negative?)
      end

      def infer_strategy_class(order)
        QuantRb::Strategy
      end

      def trade_symbol_for(position)
        return position.id unless position.multi_leg?

        position.legs.map { |leg| leg[:symbol] }.join(",")
      end
    end
  end
end
