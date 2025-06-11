require_relative "../trades/call_option"
require_relative '../trades/null_trade'
require_relative "../trades/call_spread"

module Services
  module Search
    class CallSpreadFinder
      attr_reader :symbol, :short_delta, :max_spread,
        :min_credit, :min_open_interest, :dist_from_strike, :trades, :short_legs,
        :expiration_date, :quantity, :expiration_type

      def initialize(
        symbol:,
        expiration_date: nil,
        short_delta: 0.15,
        max_spread: 20.0,
        min_credit: 100.0,
        min_open_interest: 0,
        dist_from_strike: 0.07,
        quantity: 1,
        expiration_type: nil
      )
        @symbol = symbol
        @expiration_date = expiration_date
        @short_delta = short_delta
        @max_spread = max_spread
        @min_credit = min_credit
        @min_open_interest = min_open_interest
        @dist_from_strike = dist_from_strike
        @trades = []
        @short_legs = []
        @quantity = quantity
        @expiration_type = nil
      end

      def search(opt_chain)
        # NOTE:
        # Filters the call options in the option chain to identify potential short legs
        # for a call spread strategy. The selection criteria include:
        # - Matching the specified expiration date.
        # - Having a mark price (scaled by 100) greater than or equal to the minimum credit.
        # - Ensuring the absolute delta value is within the specified range.
        # - Meeting the minimum open interest requirement.
        # - Ensuring the strike price is sufficiently distant from the underlying price
        #   based on the specified distance threshold.
        short_legs = opt_chain.call_opts.select do |option|
          option.expiration_date == expiration_date &&
            option.mark * 100.0 >= min_credit &&
            option.delta.abs <= short_delta &&
            option.delta.abs >= 0.00 &&
            option.open_interest >= min_open_interest &&
            ((opt_chain.underlying_price - option.strike) / opt_chain.underlying_price).abs >= dist_from_strike &&
            (expiration_type.nil? || option.expiration_type == expiration_type)
        end

        short_legs.each do |short_raw|
          short_leg = Services::Trades::CallOption.from_schwab_option(short_raw, quantity: quantity)

          # NOTE:
          # Filters the call options (`call_opts`) from the option chain to find potential long positions
          # that meet the following criteria:
          # - The expiration date matches the short leg's expiration date.
          # - The credit (difference between short leg's mark and long option's mark, multiplied by 100)
          #   is greater than or equal to the minimum credit (`min_credit`).
          # - The long option's strike price is greater than the short leg's strike price.
          # - The absolute difference between the long option's strike price and the short leg's strike price
          #   is less than or equal to the maximum spread (`max_spread`).
          candidate_longs = opt_chain.call_opts.select do |long_raw|
            long_raw.expiration_date == short_leg.expiration_date &&
              long_raw.mark > 0.0 &&
              ((short_leg.mark - long_raw.mark) * 100.0) >= min_credit &&
              long_raw.strike > short_leg.strike &&
              (long_raw.strike - short_leg.strike).abs <= max_spread &&
              (expiration_type.nil? || long_raw.expiration_type == expiration_type)
          end

          next unless candidate_longs.any?

          best_long_raw = candidate_longs.min_by(&:mark)
          long_leg = Services::Trades::CallOption.from_schwab_option(best_long_raw, quantity: quantity)

          @trades << Services::Trades::CallSpread.new(
            short_leg: short_leg,
            long_leg: long_leg
          )
        end

        if @trades.empty?
          Services::Trades::NullTrade.new
        else
          @trades.max_by(&:credit)
        end
      end
    end
  end
end
