# frozen_string_literal: true

module QuantRb
  module Data
    module Index
      # Synthetic-only chain index used when a backtest should explicitly price against generated chains.
      class SyntheticOptionsChainIndex
        DEFAULT_SYNTHETIC_BUSINESS_DAYS = 30

        def initialize(symbol:, synthetic_builder:, synthetic_business_days: DEFAULT_SYNTHETIC_BUSINESS_DAYS)
          @symbol = symbol
          @synthetic_builder = synthetic_builder
          @synthetic_business_days = synthetic_business_days
          @cache = {}
        end

        def chains_at(target_time, expiry_filter: nil)
          expiries = candidate_expiries(target_time, expiry_filter)

          expiries.each_with_object({}) do |expiry, result|
            chain = load_synthetic_chain(target_time, expiry)
            result[expiry] = chain if chain
          end
        end

        def available_dates
          []
        end

        private

        def load_synthetic_chain(target_time, expiry)
          cache_key = [target_time.to_i, expiry]
          @cache[cache_key] ||= @synthetic_builder.build(
            target_time: target_time,
            expiration_date: expiry,
            symbol: @symbol
          )
        rescue ArgumentError
          nil
        end

        def candidate_expiries(target_time, expiry_filter)
          return [expiry_filter] if expiry_filter.is_a?(Date)

          default_business_day_expiries(target_time.to_date).select do |expiry|
            matches_expiry_filter?(expiry, expiry_filter)
          end
        end

        def default_business_day_expiries(start_date)
          expiries = []
          date = start_date

          while expiries.length < @synthetic_business_days
            expiries << date unless date.saturday? || date.sunday?
            date += 1
          end

          expiries
        end

        def matches_expiry_filter?(expiry, expiry_filter)
          return true if expiry_filter.nil?
          return expiry_filter.call(expiry) if expiry_filter.respond_to?(:call)
          return expiry_filter.cover?(expiry) if expiry_filter.respond_to?(:cover?)
          return expiry_filter.include?(expiry) if expiry_filter.respond_to?(:include?)

          expiry == expiry_filter
        end
      end
    end
  end
end
