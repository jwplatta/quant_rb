require "schwab_rb"

class IronCondorOrder
  class << self
    def build(trade, **options)
      schwab_order_builder.new.tap do |builder|
        builder.set_account_number(options[:account_number])
        builder.set_order_strategy_type("SINGLE")
        builder.set_session(SchwabRb::Orders::Session::NORMAL)
        builder.set_duration(SchwabRb::Orders::Duration::DAY)
        builder.set_order_type(SchwabRb::Order::Types::NET_CREDIT)
        builder.set_complex_order_strategy_type(SchwabRb::Order::ComplexOrderStrategyTypes::IRON_CONDOR)
        builder.set_quantity(options[:quantity])
        # REVIEW: stocks do not need to be rounded to 5 cent
        # increments
        builder.set_price(trade.credit_debit_5_increment)
        builder.add_option_leg(
          SchwabRb::Orders::OptionInstructions::SELL_TO_OPEN,
          trade.put_spread.short_leg.symbol,
          options[:quantity]
        )
        builder.add_option_leg(
          SchwabRb::Orders::OptionInstructions::BUY_TO_OPEN,
          trade.put_spread.long_leg.symbol,
          options[:quantity]
        )
        builder.add_option_leg(
          SchwabRb::Orders::OptionInstructions::SELL_TO_OPEN,
          trade.call_spread.short_leg.symbol,
          options[:quantity]
        )
        builder.add_option_leg(
          SchwabRb::Orders::OptionInstructions::BUY_TO_OPEN,
          trade.call_spread.long_leg.symbol,
          options[:quantity]
        )
      end
    end

    def schwab_order_builder
      SchwabRb::Orders::Builder
    end
  end
end
