# frozen_string_literal: true

module Platypi
  class StrategyFinderFactory
    VALID_STRATEGIES = %w[ironcondor callspread putspread].freeze

    class << self
      def search(
        strategy_type:,
        underlying_symbol:,
        expiration_date:,
        quantity: 1,
        settlement_type: nil,
        option_root: nil,
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
          strategy_type: strategy_type,
          underlying_symbol: underlying_symbol,
          expiration_date: expiration_date,
          quantity: quantity,
          settlement_type: settlement_type,
          option_root: option_root,
          increment: increment
        ).search(
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
        strategy_type:,
        underlying_symbol:,
        expiration_date:,
        quantity: 1,
        settlement_type: nil,
        option_root: nil,
        increment: 0.01
      )
        unless VALID_STRATEGIES.include?(strategy_type.to_s.downcase)
          raise ArgumentError, "Invalid strategy type: #{strategy_type}. Valid types are: #{VALID_STRATEGIES.join(', ')}"
        end

        case strategy_type.to_s.downcase
        when 'ironcondor'
          Platypi::IronCondorFinder.new(
            underlying_symbol: underlying_symbol,
            expiration_date: expiration_date,
            quantity: quantity,
            settlement_type: settlement_type,
            option_root: option_root,
            increment: increment
          )
        when 'callspread'
          Platypi::CallSpreadFinder.new(
            underlying_symbol: underlying_symbol,
            expiration_date: expiration_date,
            quantity: quantity,
            settlement_type: settlement_type,
            option_root: option_root,
            increment: increment
          )
        when 'putspread'
          Platypi::PutSpreadFinder.new(
            underlying_symbol: underlying_symbol,
            expiration_date: expiration_date,
            quantity: quantity,
            settlement_type: settlement_type,
            option_root: option_root,
            increment: increment
          )
        end
      end

      def valid_strategy?(strategy_type)
        VALID_STRATEGIES.include?(strategy_type.to_s.downcase)
      end
    end
  end
end