# frozen_string_literal: true

module Platypi
  class StrategyFinderFactory
    VALID_STRATEGIES = %w[ironcondor callspread putspread].freeze

    class << self
      def create(
        strategy_type:,
        underlying_symbol:,
        expiration_date:,
        quantity: 1,
        settlement_type: nil,
        option_root: nil
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
            option_root: option_root
          )
        when 'callspread'
          Platypi::CallSpreadFinder.new(
            underlying_symbol: underlying_symbol,
            expiration_date: expiration_date,
            quantity: quantity,
            settlement_type: settlement_type,
            option_root: option_root
          )
        when 'putspread'
          Platypi::PutSpreadFinder.new(
            underlying_symbol: underlying_symbol,
            expiration_date: expiration_date,
            quantity: quantity,
            settlement_type: settlement_type,
            option_root: option_root
          )
        end
      end

      def valid_strategy?(strategy_type)
        VALID_STRATEGIES.include?(strategy_type.to_s.downcase)
      end
    end
  end
end