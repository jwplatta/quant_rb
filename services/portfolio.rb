require_relative "trades/call_spread"
require_relative "trades/put_spread"
require_relative "trades/iron_condor"

class Single
  def initialize(position:)
    @strategy = "SINGLE"
    @position = position
  end

  attr_reader :strategy, :position

  def to_h
    {
      strategy: strategy,
      symbols: position.symbols,
      entry_price: 0,
      exit_price: 0,
      progress: 0
    }
  end
end

class Portfolio
  class << self
    def build(orders, account)
      # TODO: would be easier to just keep track of your trades in a database
      # NOTE: for each order, see if there is an existing position or positions
      # NOTE: match the order leg with the position
      # NOTE: for any orders that contain closing and opening legs, separate
      # them into separate order objects

      orders = orders.map do |order|
        if !order.close? && !order.open?
            closing_leg_ids = order.order_leg_collection.reduce([]) do |acc, leg|
              if leg.close?
                acc << leg.leg_id
              end
              acc
            end

            opening_leg_ids = order.order_leg_collection.reduce([]) do |acc, leg|
              if leg.open?
                acc << leg.leg_id
              end
              acc
            end

            close_order = order.dup
            close_order.remove_legs(closing_leg_ids)

            open_order = order.dup
            open_order.remove_legs(opening_leg_ids)

            [close_order, open_order]
        else
          order
        end
      end.flatten

      open_orders = orders.select(&:open?).select do |order|
        !orders.select(&:close?).any? { |close_order| close_order?(order, close_order) }
      end

      open_orders.map do |open_order|
        if open_order.strategy == "PUT_SPREAD"
          PutSpread.new(
            positions: find_positions(open_order, account.positions)
          )
        elsif open_order.strategy == "CALL_SPREAD"
          CallSpread.new(
            positions: find_positions(open_order, account.positions)
          )
        elsif open_order.order_strategy_type == "SINGLE"
          Single.new(
            position: find_position(open_order, account.positions)
          )
        else
          raise "Unknown order type: #{open_order.complex_order_strategy_type}"
        end
      end.then do |positions|
        new(
          positions: positions,
          cash_balance: account.current_balances.cash_balance,
          available_funds: account.current_balances.available_funds,
          buying_power: account.current_balances.buying_power,
          buying_power_non_marginable_trade: account.current_balances.buying_power_non_marginable_trade,
          liquidation_value: account.current_balances.liquidation_value,
          maintenance_requirement: account.current_balances.maintenance_requirement
        )
      end
    end

    def find_positions(order, positions)
      positions.select { |pos| order.symbols.include? pos.symbol }
    end

    def find_position(order, positions)
      positions.find do |pos|
        order.symbols.count == 1 && order.symbols.include?(pos.symbol)
      end
    end

    def close_order?(open_order, close_order)
      return false if open_order.order_leg_collection.any? { |leg| leg.position_effect == "CLOSING" }
      return false if close_order.order_leg_collection.any? { |leg| leg.position_effect == "OPENING" }
      # return false unless open_order.complex_order_strategy_type == close_order.complex_order_strategy_type
      return false unless open_order.filled_quantity == close_order.filled_quantity

      # NOTE:
      # - symbols must match
      # - get the first leg of order a, then find the leg in order b with the same symbol
      # - check that if the first is SELL_TO_OPEN then the other is BUY_TO_CLOSE
      # or if the first is BUY_TO_OPEN then the other is SELL_TO_CLOSE
      open_order.order_leg_collection.permutation.any? do |open_leg_perm|
        close_order.order_leg_collection.zip(open_leg_perm).all? do |close_leg, open_leg|
          matching_legs?(open_leg, close_leg)
        end
      end
    end

    def matching_legs?(open_leg, close_leg)
      open_leg.symbol == close_leg.symbol && (
        (open_leg.instruction == "BUY_TO_OPEN" && close_leg.instruction == "SELL_TO_CLOSE") ||
        (open_leg.instruction == "SELL_TO_OPEN" && close_leg.instruction == "BUY_TO_CLOSE")
      )
    end
  end

  attr_reader :positions, :cash_balance, :available_funds, :buying_power,
    :buying_power_non_marginable_trade, :liquidation_value, :maintenance_requirement

  def initialize(
    positions: [], cash_balance: 0, available_funds: 0,
    buying_power: 0, buying_power_non_marginable_trade: 0,
    liquidation_value: 0, maintenance_requirement: 0
  )
    @positions = positions
    @cash_balance = cash_balance
    @available_funds = available_funds
    @buying_power = buying_power
    @buying_power_non_marginable_trade = buying_power_non_marginable_trade
    @liquidation_value = liquidation_value
    @maintenance_requirement = maintenance_requirement
  end

  def exitable?
    positions.select(&:exitable?)
  end

  def to_h
    {
      positions: positions.map(&:to_h),
      cash_balance: cash_balance,
      available_funds: available_funds,
      buying_power: buying_power,
      buying_power_non_marginable_trade: buying_power_non_marginable_trade,
      liquidation_value: liquidation_value,
      maintenance_requirement: maintenance_requirement
    }
  end

  # def to_csv
  # end
end
