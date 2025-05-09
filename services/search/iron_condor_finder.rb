require_relative "../../mixins/schwab/schwab"
require_relative "../trades/iron_condor"
require_relative "../trades/null_trade"
require_relative "call_spread_finder"
require_relative "put_spread_finder"

module Services
  module Search
    class IronCondorFinder
      include Schwab

      attr_reader :symbol, :end_date, :short_delta, :max_spread,
        :min_credit, :min_open_interest, :dist_from_strike,
        :call_spread, :put_spread, :quantity

        def initialize(
          symbol:,
          end_date: Date.today + 90,
          short_delta: 0.15,
          max_spread: 20.0,
          min_credit: 100.0,
          min_open_interest: 0,
          dist_from_strike: 0.07,
          quantity: 1
        )
        @symbol = symbol
        @end_date = end_date
        @short_delta = short_delta
        @max_spread = max_spread
        @min_credit = min_credit
        @min_open_interest = min_open_interest
        @dist_from_strike = dist_from_strike
        @trades = []
        @call_spread = nil
        @put_spread = nil
        @opt_chain = nil
        @quantity = quantity
      end

      def credit_debit
        call_spread.credit_debit + put_spread.credit_debit
      end

      def search
        @call_spread = call_spread_finder.search
        @put_spread = put_spread_finder.search

        if call_spread && put_spread
          IronCondor.new(
            call_spread: call_spread,
            put_spread: put_spread,
            expiration_date: end_date
          )
        else
          NullTrade.new
        end
      end

      def opt_chain
        @opt_chain ||= option_chain(
          symbol,
          strike_range: "OTM",
          to_date: end_date,
        )
      end

      def call_spread_finder
        @call_spread_finder ||= CallSpreadFinder.new(
          symbol: symbol,
          expiration_date: end_date,
          short_delta: short_delta,
          max_spread: max_spread,
          min_credit: min_credit,
          min_open_interest: min_open_interest,
          dist_from_strike: dist_from_strike,
          opt_chain: opt_chain,
          quantity: quantity
        )
      end

      def put_spread_finder
        @put_spread_finder ||= PutSpreadFinder.new(
          symbol: symbol,
          expiration_date: end_date,
          short_delta: short_delta,
          max_spread: max_spread,
          min_credit: min_credit,
          min_open_interest: min_open_interest,
          dist_from_strike: dist_from_strike,
          opt_chain: opt_chain,
          quantity: quantity
        )
      end
    end
  end
end
