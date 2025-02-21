require "schwab_rb"
require_relative "iron_condor_order"
require_relative "vertical_order"

class OrderFactory
  class << self
    def build(trade, **options)
      case trade.strategy
      when SchwabRb::Order::ComplexOrderStrategyTypes::IRON_CONDOR
        IronCondorOrder.build(trade, **options)
      when SchwabRb::Order::ComplexOrderStrategyTypes::VERTICAL
        VerticalOrder.build(trade, **options)
      else
        raise "Unsupported trade strategy"
      end
    end
  end
end