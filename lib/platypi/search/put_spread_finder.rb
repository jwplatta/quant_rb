# frozen_string_literal: true

module Platypi
  # Put spread finder for searching options
  class PutSpreadFinder
    include Platypi::Schwab

    attr_reader :underlying_symbol, :short_delta, :max_spread,
                :min_credit, :min_open_interest, :dist_from_strike, :trades, :short_legs, :expiration_date, :quantity, :expiration_type, :settlement_type, :option_root

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
      @trades = []
      @short_legs = []
      @quantity = quantity
      @expiration_type = expiration_type
      @settlement_type = settlement_type
      @option_root = option_root
    end

    def search(opt_chain_or_params = nil, from_date: nil, to_date: nil)
      # Handle both direct option chain and option chain parameters
      if opt_chain_or_params.respond_to?(:put_opts)
        # Called from IronCondorFinder with actual option chain data
        opt_chain = opt_chain_or_params
      else
        # Called independently - load option chain internally with PUT contract type
        opt_chain = option_chain(
          underlying_symbol,
          contract_type: 'PUT',
          from_date: from_date || expiration_date,
          to_date: to_date || expiration_date
        )
      end

      return NullStrategy.new unless opt_chain

      short_legs = opt_chain.put_opts.select do |option|
        option.expiration_date == expiration_date &&
          option.mark * 100.0 >= min_credit &&
          option.delta.abs <= short_delta &&
          option.delta.abs >= 0.00 &&
          option.open_interest >= min_open_interest &&
          ((opt_chain.underlying_price - option.strike) / opt_chain.underlying_price).abs >= dist_from_strike &&
          (expiration_type.nil? || option.expiration_type == expiration_type) &&
          (settlement_type.nil? || option.settlement_type == settlement_type) &&
          (option_root.nil? || option.option_root == option_root)
      end

      short_legs.each do |short_raw|
        short_leg = PutOption.from_schwab_option(
          short_raw,
          quantity: quantity
        )

        potential_longs = opt_chain.put_opts.select do |long_raw|
          long_raw.expiration_date == short_leg.expiration_date &&
            long_raw.mark > 0.0 &&
            ((short_leg.mark - long_raw.mark) * 100.0).round >= min_credit &&
            long_raw.strike < short_leg.strike &&
            (short_leg.strike - long_raw.strike) <= max_spread &&
            (expiration_type.nil? || long_raw.expiration_type == expiration_type) &&
            (settlement_type.nil? || long_raw.settlement_type == settlement_type) &&
            (option_root.nil? || long_raw.option_root == option_root)
        end

        next unless potential_longs.any?

        best_long_raw = potential_longs.min_by(&:mark)
        long_leg = PutOption.from_schwab_option(
          best_long_raw,
          quantity: quantity
        )

        @trades << PutSpread.new(
          underlying_symbol: underlying_symbol,
          short_leg: short_leg,
          long_leg: long_leg
        )
      end

      if @trades.empty?
        NullStrategy.new
      else
        @trades.max_by(&:credit)
      end
    end
  end
end

