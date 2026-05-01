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

      def record_fill(order, fill_price, fill_time, strategy_class: nil, transaction_costs: nil)
        transaction_costs ||= QuantRb::Reality::CostBreakdown.new
        if order.multi_leg?
          record_multi_leg_fill(order, fill_price, fill_time, transaction_costs: transaction_costs)
        else
          record_single_leg_fill(
            order,
            fill_price,
            fill_time,
            strategy_class: strategy_class,
            transaction_costs: transaction_costs
          )
        end
      end

      def close_position(order_id, close_price, close_time, strategy_class: nil, notes: nil, transaction_costs: nil)
        transaction_costs ||= QuantRb::Reality::CostBreakdown.new
        position = @positions.delete(order_id)
        return unless position

        adjust_cash(
          if position.multi_leg?
            combo_close_cash_flow(position, close_price)
          else
            position.quantity * close_price.to_f
          end
        )
        adjust_cash(-transaction_costs.total)

        trade_history << build_trade_record(
          position: position,
          close_price: close_price,
          close_time: close_time,
          strategy_class: strategy_class,
          notes: notes,
          exit_fees: transaction_costs.fees,
          exit_commissions: transaction_costs.commissions
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

      def process_expirations(slice, strategy_class: nil)
        positions.keys.each do |position_id|
          position = positions[position_id]
          next unless position&.option_position?
          next unless expiration_due?(position, slice.time)

          spot = expiration_spot(position, slice)
          next if spot.nil?

          settlement_price = option_settlement_price(position, spot)
          close_position(
            position.id,
            settlement_price,
            slice.time,
            strategy_class: strategy_class,
            notes: "Automatic option expiration settlement"
          )
        end
      end

      private

      def record_multi_leg_fill(order, fill_price, fill_time, transaction_costs:)
        position = QuantRb::Engine::Position.new(
          id: order.id,
          order: order,
          quantity: order.quantity,
          entry_price: fill_price,
          entry_time: fill_time,
          direction: order.credit? ? :credit : :debit,
          current_price: fill_price,
          entry_fees: transaction_costs.fees,
          entry_commissions: transaction_costs.commissions,
          expiration_date: infer_expiration_date(order.legs),
          underlying_symbol: infer_underlying_symbol(order.legs)
        )

        @positions[position.id] = position
        adjust_cash(combo_open_cash_flow(order, fill_price))
        adjust_cash(-transaction_costs.total)
      end

      def record_single_leg_fill(order, fill_price, fill_time, strategy_class:, transaction_costs:)
        symbol = order.symbol.to_sym
        signed_quantity = order.signed_quantity

        adjust_cash(-(fill_price.to_f * signed_quantity))
        adjust_cash(-transaction_costs.total)

        existing = @positions[symbol]
        unless existing
          @positions[symbol] = build_single_leg_position(
            symbol,
            order,
            signed_quantity,
            fill_price,
            fill_time,
            transaction_costs
          )
          return
        end

        if same_direction?(existing.direction, signed_quantity)
          scale_position(existing, signed_quantity, fill_price, transaction_costs)
          return
        end

        close_against_position(
          symbol: symbol,
          existing: existing,
          order: order,
          signed_quantity: signed_quantity,
          fill_price: fill_price,
          fill_time: fill_time,
          strategy_class: strategy_class,
          transaction_costs: transaction_costs
        )
      end

      def build_single_leg_position(symbol, order, signed_quantity, fill_price, fill_time, transaction_costs)
        QuantRb::Engine::Position.new(
          id: symbol,
          order: order,
          quantity: signed_quantity.abs,
          entry_price: fill_price,
          entry_time: fill_time,
          direction: signed_quantity.positive? ? :long : :short,
          current_price: fill_price,
          entry_fees: transaction_costs.fees,
          entry_commissions: transaction_costs.commissions,
          expiration_date: infer_expiration_date(order.legs),
          underlying_symbol: infer_underlying_symbol(order.legs)
        )
      end

      def scale_position(position, signed_quantity, fill_price, transaction_costs)
        added_quantity = signed_quantity.abs
        total_quantity = position.quantity + added_quantity
        weighted_entry = ((position.entry_price * position.quantity) + (fill_price.to_f * added_quantity)) / total_quantity

        position.entry_price = weighted_entry
        position.quantity = total_quantity
        position.current_price = fill_price.to_f
        position.instance_variable_set(:@entry_fees, position.entry_fees + transaction_costs.fees)
        position.instance_variable_set(:@entry_commissions, position.entry_commissions + transaction_costs.commissions)
      end

      def close_against_position(symbol:, existing:, order:, signed_quantity:, fill_price:, fill_time:, strategy_class:, transaction_costs:)
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
          legs: existing.legs,
          entry_fees: existing.entry_fees,
          entry_commissions: existing.entry_commissions,
          exit_fees: transaction_costs.fees,
          exit_commissions: transaction_costs.commissions
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
        @positions[symbol] = build_single_leg_position(
          symbol,
          order,
          net_signed_quantity,
          fill_price,
          fill_time,
          transaction_costs
        )
      end

      def build_trade_record(position:, close_price:, close_time:, strategy_class:, notes:, exit_fees:, exit_commissions:)
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
          notes: notes,
          entry_fees: position.entry_fees,
          entry_commissions: position.entry_commissions,
          exit_fees: exit_fees,
          exit_commissions: exit_commissions
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

      def adjust_cash(amount)
        @cash = (@cash + amount.to_f).round(4)
      end

      def infer_expiration_date(legs)
        dates = Array(legs).map { |leg| leg[:expiration_date] }.compact.uniq
        dates.one? ? dates.first : nil
      end

      def infer_underlying_symbol(legs)
        Array(legs).map { |leg| leg[:underlying_symbol] }.compact.uniq.first
      end

      def expiration_due?(position, current_time)
        return false unless position.expiration_date

        current_time.to_date >= position.expiration_date
      end

      def expiration_spot(position, slice)
        symbol = position.underlying_symbol
        return nil if symbol.to_s.empty?

        candle = slice.bars[symbol.to_sym] || slice.bars[symbol.to_s]
        candle&.close&.to_f
      end

      def option_settlement_price(position, spot)
        signed_leg_value = position.legs.sum do |leg|
          leg[:quantity].to_i * intrinsic_value_for_leg(leg, spot)
        end

        position.direction == :credit ? -signed_leg_value : signed_leg_value
      end

      def intrinsic_value_for_leg(leg, spot)
        strike = leg[:strike].to_f
        case leg[:put_call].to_s.upcase
        when QuantRb::CALL
          [spot - strike, 0.0].max
        when QuantRb::PUT
          [strike - spot, 0.0].max
        else
          0.0
        end
      end
    end
  end
end
