require "schwab_rb"

class VerticalOrder
  class << self
    def build(trade, **options)
      schwab_order_builder.new.tap do |builder|
        builder.set_account_number(options[:account_number])
        builder.set_order_strategy_type("SINGLE")
        builder.set_session(SchwabRb::Orders::Session::NORMAL)
        builder.set_duration(SchwabRb::Orders::Duration::DAY)
        builder.set_order_type(SchwabRb::Order::Types::NET_CREDIT)
        builder.set_complex_order_strategy_type(SchwabRb::Order::ComplexOrderStrategyTypes::VERTICAL)
        builder.set_quantity(options[:quantity])
        builder.set_price(trade.credit_debit)
        builder.add_option_leg(
          SchwabRb::Orders::OptionInstructions::SELL_TO_OPEN,
          trade.short_call.symbol,
          options[:quantity]
        )
        builder.add_option_leg(
          SchwabRb::Orders::OptionInstructions::BUY_TO_OPEN,
          trade.long_call.symbol,
          options[:quantity]
        )
      end
    end

    def schwab_order_builder
      SchwabRb::Orders::Builder
    end
  end
end