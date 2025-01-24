class ComplexStrategyPosition
  attr_reader :strategy, :positions

  def initialize(strategy:, positions:, exit_threshold: 0.75)
    # NOTE: right assuming a put spread
    @strategy = strategy
    @positions = positions
    @exit_threshold = exit_threshold
  end

  def symbols
    positions.map(&:symbol)
  end

  def exitable?
    progress >= @exit_threshold
  end

  def progress
    1 - (exit_price * -1 / entry_price)
  end

  def entry_price
    @entry_price ||= (long_leg.average_price * 100 * -1) + (short_leg.average_price * 100)
  end

  def exit_price
    @exit_price ||= long_leg.market_value + short_leg.market_value
  end

  def short_leg
    @short_leg ||= positions.find { |p| p.short_quantity.positive? }
  end

  def long_leg
    @long_leg ||= positions.find { |p| p.long_quantity.positive? }
  end
end

class Portfolio
  class << self
    def build(orders, account)
      # NOTE: for each order, see if there is an existing position or positions
      positions = orders.map do |order|
        curr_position = account.positions.select do |position|
          order.symbols.include?(position.symbol)
        end

        if curr_position.count > 1
          ComplexStrategyPosition.new(
            strategy: order.complex_order_strategy_type,
            positions: curr_position
          )
        else
          curr_position.first
        end
      end

      new(
        positions: positions
      )
    end
  end

  attr_reader :positions

  def initialize(positions:)
    @positions = positions
  end

  def exitable?
    positions.select(&:exitable?)
  end

  def at_risk?
  end
end
