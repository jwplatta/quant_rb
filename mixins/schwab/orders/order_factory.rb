# frozen_string_literal: true

require 'schwab_rb'
require_relative 'iron_condor_order'
require_relative 'vertical_order'

VERTICAL_TRADES = [
  'Services::Trades::PutSpread',
  'Services::Trades::CallSpread',
]

SINGLE_TRADES = [
  'Services::Trades::CallOption',
  'Services::Trades::PutOption',
]

class OrderFactory
  class << self
    def build(trade, **options)
      # NOTE: raise ArgumentError, 'Trade must be a Services::Trade' unless trade.is_a?(Trade)
      case strategy_type(trade)
      when SchwabRb::Order::ComplexOrderStrategyTypes::IRON_CONDOR
        IronCondorOrder.build(trade, **options)
      when SchwabRb::Order::ComplexOrderStrategyTypes::VERTICAL
        VerticalOrder.build(trade, **options)
      else
        raise 'Unsupported trade strategy'
      end
    end

    def strategy_type(trade)
      if trade.class.name == 'Services::Trades::IronCondor'
        'IRON_CONDOR'
      elsif VERTICAL_TRADES.include?(trade.class.name)
        'VERTICAL'
      elsif SINGLE_TRADES.include?(trade.class.name)
        'SINGLE'
      else
        raise ArgumentError, "Unsupported trade type: #{trade.class.name}"
      end
    end
  end
end
