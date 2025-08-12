# frozen_string_literal: true

module OptionsTrader
  class IronCondorSearch
    include OptionsTrader::Schwab

    attr_reader :underlying_symbol, :expiration_date,
                :quantity, :expiration_type,
                :option_root, :settlement_type, :increment

    def initialize(
      underlying_symbol:,
      expiration_date: nil,
      expiration_type: nil,
      settlement_type: nil,
      option_root: nil,
      quantity: 1,
      increment: 0.01
    )
      @underlying_symbol = underlying_symbol
      @expiration_date = expiration_date
      @quantity = quantity
      @expiration_type = expiration_type
      @settlement_type = settlement_type
      @option_root = option_root
      @increment = increment
    end

    def find(
      from_date: nil,
      to_date: nil,
      short_delta: 0.15,
      max_spread: 20.0,
      min_credit: 100.0,
      min_open_interest: 0,
      dist_from_strike: 0.07
    )
      opt_chain = option_chain(
        underlying_symbol,
        contract_type: 'ALL',
        strike_range: 'OTM',
        to_date: to_date || expiration_date,
        from_date: from_date || expiration_date
      )

      return NullStrategy.new unless opt_chain

      call_spreads = call_spread_search(
        max_spread: max_spread,
        min_open_interest: min_open_interest,
        dist_from_strike: dist_from_strike
      ).find(
        opt_chain,
        return_spreads: true,
        short_delta: short_delta,
        max_spread: max_spread,
        min_open_interest: min_open_interest,
        dist_from_strike: dist_from_strike
      )
      return NullStrategy.new if call_spreads.empty?

      put_spreads = put_spread_search(
        max_spread: max_spread,
        min_open_interest: min_open_interest,
        dist_from_strike: dist_from_strike
      ).find(
        opt_chain,
        return_spreads: true,
        short_delta: short_delta,
        max_spread: max_spread,
        min_open_interest: min_open_interest,
        dist_from_strike: dist_from_strike
      )
      return NullStrategy.new if put_spreads.empty?

      all_combos = call_spreads.product(put_spreads)

      all_combos_with_min_credit = all_combos.select do |call_sprd, put_sprd|
        (call_sprd.credit + put_sprd.credit) * 100 >= min_credit
      end

      # NOTE: Selects the best combination of call and put spreads from all_combos_with_min_credit
      # by maximizing the ratio of total credit received to the sum of the absolute deltas.
      # This favors combinations that offer higher credit relative to risk (as measured by delta).
      call_spread, put_spread = all_combos_with_min_credit.max_by do |call_sprd, put_sprd|
        (call_sprd.credit + put_sprd.credit) / (call_sprd.delta.abs + put_sprd.delta.abs)
      end

      if call_spread.is_a?(CallSpread) && put_spread.is_a?(PutSpread)
        IronCondor.new(
          underlying_symbol: underlying_symbol,
          call_spread: call_spread,
          put_spread: put_spread,
          quantity: quantity,
          increment: increment
        )
      else
        NullStrategy.new
      end
    end

    private

    def call_spread_search(max_spread:, min_open_interest:, dist_from_strike:)
      VerticalSpreadSearch.new(
        underlying_symbol: underlying_symbol,
        put_call: 'CALL',
        quantity: quantity,
        expiration_type: expiration_type,
        settlement_type: settlement_type,
        option_root: option_root,
        increment: increment,
        expiration_date: expiration_date
      )
    end

    def put_spread_search(max_spread:, min_open_interest:, dist_from_strike:)
      VerticalSpreadSearch.new(
        underlying_symbol: underlying_symbol,
        put_call: 'PUT',
        quantity: quantity,
        expiration_type: expiration_type,
        settlement_type: settlement_type,
        option_root: option_root,
        increment: increment,
        expiration_date: expiration_date
      )
    end
  end
end
