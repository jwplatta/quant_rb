# frozen_string_literal: true

module OptionsTrader
  class StrategySearchFactory
    class << self
      def find(
        markets_service:,
        strategy_type:,
        underlying_symbol:,
        expiration_date:,
        option_root: nil,
        put_call: nil,
        quantity: 1,
        expiration_type: nil,
        settlement_type: nil,
        from_date: nil,
        to_date: nil,
        short_delta: 0.05,
        max_spread: 10.0,
        min_credit: 100.0,
        min_open_interest: 0,
        dist_from_strike: 0.01,
        increment: 0.01
      )
        create(
          markets_service: markets_service,
          strategy_type: strategy_type,
          underlying_symbol: underlying_symbol,
          put_call: put_call,
          expiration_date: expiration_date,
          quantity: quantity,
          settlement_type: settlement_type,
          expiration_type: expiration_type,
          option_root: option_root,
          increment: increment
        ).find(
          from_date: from_date,
          to_date: to_date,
          short_delta: short_delta,
          max_spread: max_spread,
          min_credit: min_credit,
          min_open_interest: min_open_interest,
          dist_from_strike: dist_from_strike
        )
      end

      def create(
        markets_service:,
        strategy_type:,
        underlying_symbol:,
        expiration_date:,
        option_root:,
        put_call: nil,
        quantity: 1,
        settlement_type: nil,
        expiration_type: nil,
        increment: 0.01
      )
        unless valid_strategies.include?(strategy_type.to_s.downcase)
          raise ArgumentError, "Invalid strategy type: #{strategy_type}. Valid types are: #{valid_strategies.join(', ')}"
        end

        case strategy_type.to_s.downcase
        when 'ironcondor'
          OptionsTrader::IronCondorSearch.new(
            markets_service: markets_service,
            underlying_symbol: underlying_symbol,
            expiration_date: expiration_date,
            quantity: quantity,
            settlement_type: settlement_type,
            expiration_type: expiration_type,
            option_root: option_root,
            increment: increment
          )
        when 'vertical'
          OptionsTrader::VerticalSpreadSearch.new(
            markets_service: markets_service,
            underlying_symbol: underlying_symbol,
            put_call: put_call,
            expiration_date: expiration_date,
            quantity: quantity,
            settlement_type: settlement_type,
            expiration_type: expiration_type,
            option_root: option_root,
            increment: increment
          )
        when 'single'
          OptionsTrader::SingleOptionSearch.new(
            markets_service: markets_service,
            underlying_symbol: underlying_symbol,
            put_call: put_call,
            expiration_date: expiration_date,
            quantity: quantity,
            settlement_type: settlement_type,
            expiration_type: expiration_type,
            option_root: option_root,
            increment: increment
          )
        end
      end

      def valid_strategy?(strategy_type)
        valid_strategies.include?(strategy_type.to_s.downcase)
      end

      def valid_strategies
        OptionsTrader::VALID_STRATEGIES
      end
    end
  end
end
