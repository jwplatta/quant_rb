# frozen_string_literal: true

module Platypi
  # Iron condor finder for searching options
  class IronCondorFinder
    include Platypi::Schwab

    attr_reader :underlying_symbol, :expiration_date, :short_delta, :max_spread,
                :min_credit, :min_open_interest, :dist_from_strike,
                :call_spread, :put_spread, :quantity, :expiration_type,
                :option_root, :settlement_type

    def initialize(
      underlying_symbol:,
      expiration_date: nil,
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
      @underlying_symbol = underlying_symbol
      @expiration_date = expiration_date
      @short_delta = short_delta
      @max_spread = max_spread
      @min_credit = min_credit
      @min_open_interest = min_open_interest
      @dist_from_strike = dist_from_strike
      @quantity = quantity
      @expiration_type = expiration_type
      @settlement_type = settlement_type
      @option_root = option_root
      @call_spread = nil
      @put_spread = nil
    end

    def search(from_date: nil, to_date: nil)
      opt_chain = option_chain(
        underlying_symbol,
        contract_type: 'ALL',
        from_date: from_date || expiration_date,
        to_date: to_date || expiration_date
      )

      return NullStrategy.new unless opt_chain

      @call_spread = call_spread_finder.search(opt_chain)
      @put_spread = put_spread_finder.search(opt_chain)

      if call_spread.is_a?(CallSpread) && put_spread.is_a?(PutSpread)
        IronCondor.new(
          underlying_symbol: underlying_symbol,
          call_spread: call_spread,
          put_spread: put_spread,
          expiration_date: expiration_date,
          quantity: quantity
        )
      else
        NullStrategy.new
      end
    end

    def call_spread_finder
      @call_spread_finder ||= CallSpreadFinder.new(
        underlying_symbol: underlying_symbol,
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
        underlying_symbol: underlying_symbol,
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
