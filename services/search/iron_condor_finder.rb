# frozen_string_literal: true

require_relative '../trades/iron_condor'
require_relative '../trades/null_trade'
require_relative 'call_spread_finder'
require_relative 'put_spread_finder'

module Services
  module Search
    class IronCondorFinder
      attr_reader :symbol, :expiration_date, :short_delta, :max_spread,
                  :min_credit, :min_open_interest, :dist_from_strike,
                  :call_spread, :put_spread, :quantity, :expiration_type,
                  :option_root, :settlement_type

      def initialize(
        symbol:,
        expiration_date: Date.today + 90,
        short_delta: 0.15,
        max_spread: 20.0,
        min_credit: 100.0,
        min_open_interest: 0,
        dist_from_strike: 0.07,
        quantity: 1,
        expiration_type: nil,
        settlement_type: nil,
        option_root: nil
      )
        @symbol = symbol
        @expiration_date = expiration_date
        @short_delta = short_delta
        @max_spread = max_spread
        @min_credit = min_credit
        @min_open_interest = min_open_interest
        @dist_from_strike = dist_from_strike
        @trades = []
        @call_spread = nil
        @put_spread = nil
        @quantity = quantity,
        @expiration_type = expiration_type
        @settlement_type = settlement_type
        @option_root = option_root
      end

      def credit_debit
        call_spread.credit_debit + put_spread.credit_debit
      end

      def search(opt_chain)
        @call_spread = call_spread_finder.search(opt_chain)
        @put_spread = put_spread_finder.search(opt_chain)

        if call_spread && put_spread
          IronCondor.new(
            call_spread: call_spread,
            put_spread: put_spread,
            expiration_date: expiration_date,
          )
        else
          NullTrade.new
        end
      end

      def call_spread_finder
        @call_spread_finder ||= CallSpreadFinder.new(
          symbol: symbol,
          expiration_date: expiration_date,
          short_delta: short_delta,
          max_spread: max_spread,
          min_credit: min_credit,
          min_open_interest: min_open_interest,
          dist_from_strike: dist_from_strike,
          quantity: quantity,
          expiration_type: expiration_type,
          settlement_type: settlement_type,
          option_root: option_root
        )
      end

      def put_spread_finder
        @put_spread_finder ||= PutSpreadFinder.new(
          symbol: symbol,
          expiration_date: expiration_date,
          short_delta: short_delta,
          max_spread: max_spread,
          min_credit: min_credit,
          min_open_interest: min_open_interest,
          dist_from_strike: dist_from_strike,
          quantity: quantity,
          expiration_type: expiration_type,
          settlement_type: settlement_type,
          option_root: option_root
        )
      end
    end
  end
end
