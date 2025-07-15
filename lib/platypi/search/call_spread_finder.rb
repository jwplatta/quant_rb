# frozen_string_literal: true

module Platypi
  class CallSpreadFinder
    include Platypi::Schwab

    attr_reader :underlying_symbol, :spreads, :short_legs,
      :expiration_date, :quantity, :expiration_type,
      :settlement_type, :option_root, :increment

    def initialize(
      underlying_symbol:,
      expiration_date: nil,
      quantity: 1,
      expiration_type: nil,
      settlement_type: nil,
      option_root: nil,
      increment: 0.01
    )
      @underlying_symbol = underlying_symbol
      @expiration_date = expiration_date
      @spreads = []
      @short_legs = []
      @quantity = quantity
      @expiration_type = expiration_type
      @settlement_type = settlement_type
      @option_root = option_root
      @increment = increment
    end

    def search(
      opt_chain_or_params = nil,
      from_date: nil,
      to_date: nil,
      return_spreads: false,
      short_delta: 0.15,
      max_spread: 20.0,
      min_credit: nil,
      min_open_interest: 0,
      dist_from_strike: 0.07
    )
      opt_chain = if opt_chain_or_params.respond_to?(:call_opts)
        opt_chain_or_params
      else
        option_chain(
          underlying_symbol,
          contract_type: 'CALL',
          from_date: from_date || expiration_date,
          to_date: to_date || expiration_date
        )
      end

      return NullStrategy.new unless opt_chain

      # NOTE:
      # Filters the call options in the option chain to identify potential short legs
      # for a call spread strategy. The selection criteria include:
      # - Matching the specified expiration date.
      # - Having a mark price (scaled by 100) greater than or equal to the minimum credit (if specified).
      # - Ensuring the absolute delta value is within the specified range.
      # - Meeting the minimum open interest requirement.
      # - Ensuring the strike price is sufficiently distant from the underlying price
      #   based on the specified distance threshold.
      short_legs = opt_chain.call_opts.select do |option|
        option.expiration_date == expiration_date &&
          (min_credit.nil? || option.mark * 100.0 >= min_credit) &&
          option.delta.abs <= short_delta &&
          option.delta.abs >= 0.00 &&
          option.open_interest >= min_open_interest &&
          ((opt_chain.underlying_price - option.strike) / opt_chain.underlying_price).abs >= dist_from_strike &&
          (expiration_type.nil? || option.expiration_type == expiration_type) &&
          (settlement_type.nil? || option.settlement_type == settlement_type) &&
          (option_root.nil? || option.option_root == option_root)
      end

      short_legs.each do |short_raw|
        short_leg = CallOption.from_schwab_option(short_raw, quantity: quantity)

        # NOTE:
        # Filters the call options (`call_opts`) from the option chain to find potential long positions
        # that meet the following criteria:
        # - The expiration date matches the short leg's expiration date.
        # - The credit (difference between short leg's mark and long option's mark, multiplied by 100)
        #   is greater than or equal to the minimum credit (if specified).
        # - The long option's strike price is greater than the short leg's strike price.
        # - The absolute difference between the long option's strike price and the short leg's strike price
        #   is less than or equal to the maximum spread (`max_spread`).
        candidate_longs = opt_chain.call_opts.select do |long_raw|
          long_raw.expiration_date == short_leg.expiration_date &&
            long_raw.mark > 0.0 &&
            (min_credit.nil? || ((short_leg.mark - long_raw.mark) * 100.0).round >= min_credit) &&
            long_raw.strike > short_leg.strike &&
            (long_raw.strike - short_leg.strike) <= max_spread &&
            (expiration_type.nil? || long_raw.expiration_type == expiration_type) &&
            (settlement_type.nil? || long_raw.settlement_type == settlement_type) &&
            (option_root.nil? || long_raw.option_root == option_root)
        end

        next unless candidate_longs.any?

        best_long_raw = candidate_longs.min_by(&:mark)
        long_leg = CallOption.from_schwab_option(best_long_raw, quantity: quantity)

        @spreads << CallSpread.new(
          underlying_symbol: underlying_symbol,
          increment: increment,
          short_leg: short_leg,
          long_leg: long_leg
        )
      end

      return spreads if return_spreads

      if spreads.empty?
        NullStrategy.new
      else
        spreads.max_by(&:credit)
      end
    end
  end
end
