require "schwab_rb"

class IronCondorOrder
  class << self
    def build(trade, **options)
      position_type = options[:position_type] || :entry

      schwab_order_builder.new.tap do |builder|
        builder.set_account_number(options[:account_number])
        builder.set_order_strategy_type("SINGLE")
        builder.set_session(SchwabRb::Orders::Session::NORMAL)
        builder.set_duration(SchwabRb::Orders::Duration::DAY)
        builder.set_order_type(SchwabRb::Order::Types::NET_CREDIT)
        builder.set_complex_order_strategy_type(SchwabRb::Order::ComplexOrderStrategyTypes::IRON_CONDOR)
        builder.set_quantity(options[:quantity])
        builder.set_price(trade.credit_debit)

        instructions = leg_instructions_for_position(position_type)

        builder.add_option_leg(
          instructions[:put_short],
          trade.put_spread.short_leg.symbol,
          options[:quantity]
        )
        builder.add_option_leg(
          instructions[:put_long],
          trade.put_spread.long_leg.symbol,
          options[:quantity]
        )
        builder.add_option_leg(
          instructions[:call_short],
          trade.call_spread.short_leg.symbol,
          options[:quantity]
        )
        builder.add_option_leg(
          instructions[:call_long],
          trade.call_spread.long_leg.symbol,
          options[:quantity]
        )
      end
    end

    def leg_instructions_for_position(position_type)
      case position_type
      when :entry
        {
          put_short: SchwabRb::Orders::OptionInstructions::SELL_TO_OPEN,
          put_long: SchwabRb::Orders::OptionInstructions::BUY_TO_OPEN,
          call_short: SchwabRb::Orders::OptionInstructions::SELL_TO_OPEN,
          call_long: SchwabRb::Orders::OptionInstructions::BUY_TO_OPEN
        }
      when :exit
        {
          put_short: SchwabRb::Orders::OptionInstructions::BUY_TO_CLOSE,
          put_long: SchwabRb::Orders::OptionInstructions::SELL_TO_CLOSE,
          call_short: SchwabRb::Orders::OptionInstructions::BUY_TO_CLOSE,
          call_long: SchwabRb::Orders::OptionInstructions::SELL_TO_CLOSE
        }
      end
    end

    def schwab_order_builder
      SchwabRb::Orders::Builder
    end
  end
end
