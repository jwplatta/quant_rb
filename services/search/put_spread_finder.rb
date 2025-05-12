require 'pry'
require_relative '../trades/put_option'
require_relative '../trades/put_spread'

module Services
  module Search
    class PutSpreadFinder
      attr_reader :symbol, :short_delta, :max_spread,
                  :min_credit, :min_open_interest, :dist_from_strike, :trades, :short_legs,
                  :expiration_date, :quantity, :opt_chain

      def initialize(
        symbol:,
        expiration_date: nil,
        short_delta: 0.15,
        max_spread: 20.0,
        min_credit: 100.0,
        min_open_interest: 0,
        dist_from_strike: 0.07,
        opt_chain: nil,
        quantity: 1
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
        @opt_chain = opt_chain
        @quantity = quantity
      end

      def search
        short_legs = opt_chain.put_opts.select do |option|
          option.expiration_date == expiration_date #&&
            option.mark * 100.0 >= min_credit &&
            option.delta.abs <= short_delta &&
            option.delta.abs >= 0.00 &&
            option.open_interest >= min_open_interest &&
            ((opt_chain.underlying_price - option.strike) / opt_chain.underlying_price).abs >= dist_from_strike
        end

        short_legs.each do |short_raw|
          short_leg = Services::Trades::PutOption.new(
            short_raw.symbol,
            strike: short_raw.strike,
            delta: short_raw.delta,
            mark: short_raw.mark,
            ask: short_raw.ask,
            bid: short_raw.bid,
            expiration_date: short_raw.expiration_date,
            quantity: quantity
          )
          # TODO: just needs to meet the condition of not being
          # too far away and the same expiration date
          potential_longs = short_legs.select do |long_raw|
            long_raw.expiration_date == short_leg.expiration_date &&
              (short_leg.mark * 100.0 - long_raw.mark * 100.0) >= min_credit &&
              long_raw.strike < short_leg.strike &&
              (long_raw.strike - short_leg.strike).abs <= max_spread
          end

          next unless potential_longs.any?

          best_long_raw = potential_longs.min_by(&:mark)
          long_leg = Services::Trades::PutOption.new(
            best_long_raw.symbol,
            strike: best_long_raw.strike,
            delta: best_long_raw.delta,
            mark: best_long_raw.mark,
            ask: best_long_raw.ask,
            bid: best_long_raw.bid,
            expiration_date: best_long_raw.expiration_date,
            quantity: quantity
          )

          @trades << Services::Trades::PutSpread.new(
            short_leg: short_leg,
            long_leg: long_leg
          )
        end

        @trades.max_by(&:credit_debit)
      end
    end
  end
end

