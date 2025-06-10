# frozen_string_literal: true

require 'schwab_rb'

class VerticalOrder
  class << self
    def build(trade, **options)
      order_instruction = options[:order_instruction] || :open
      quantity = options[:quantity] || 1

      schwab_order_builder.new.tap do |builder|
        builder.set_account_number(options[:account_number])
        builder.set_order_strategy_type('SINGLE')
        builder.set_session(SchwabRb::Orders::Session::NORMAL)
        builder.set_duration(SchwabRb::Orders::Duration::DAY)
        builder.set_order_type(order_type(order_instruction))
        builder.set_complex_order_strategy_type(SchwabRb::Order::ComplexOrderStrategyTypes::VERTICAL)
        builder.set_quantity(quantity)
        builder.set_price(trade.credit)
        builder.add_option_leg(
          short_leg_instruction(order_instruction),
          trade.short_leg.symbol,
          quantity
        )
        builder.add_option_leg(
          long_leg_instruction(order_instruction),
          trade.long_leg.symbol,
          quantity
        )
      end
    end

    def price(trade, order_instruction)
      if order_instruction == :open
        trade.credit
      elsif order_instruction == :exit
        trade.debit.abs
      end
    end

    def order_type(order_instruction)
      if order_instruction == :open
        SchwabRb::Order::Types::NET_CREDIT
      else
        SchwabRb::Order::Types::NET_DEBIT
      end
    end

    def short_leg_instruction(order_instruction)
      if order_instruction == :open
        SchwabRb::Orders::OptionInstructions::SELL_TO_OPEN
      else
        SchwabRb::Orders::OptionInstructions::BUY_TO_CLOSE
      end
    end

    def long_leg_instruction(order_instruction)
      if order_instruction == :open
        SchwabRb::Orders::OptionInstructions::BUY_TO_OPEN
      else
        SchwabRb::Orders::OptionInstructions::SELL_TO_CLOSE
      end
    end

    def schwab_order_builder
      SchwabRb::Orders::Builder
    end
  end
end
