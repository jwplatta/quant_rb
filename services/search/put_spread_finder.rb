require_relative '../trades/put_option'
require_relative '../trades/null_trade'
require_relative '../trades/put_spread'

module Services
  module Search
    class PutSpreadFinder
      attr_reader :symbol, :short_delta, :max_spread,
                  :min_credit, :min_open_interest, :dist_from_strike, :trades, :short_legs, :expiration_date, :quantity, :expiration_type, :settlement_type, :option_root

      def initialize(
        symbol:,
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
        @expiration_type = expiration_type
        @settlement_type = settlement_type
        @option_root = option_root
      end

      def search(opt_chain)
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
          short_leg = Services::Trades::PutOption.from_schwab_option(
            short_raw,
            quantity: quantity
          )

          potential_longs = short_legs.select do |long_raw|
            long_raw.expiration_date == short_leg.expiration_date &&
              long_raw.mark > 0.0 &&
              ((short_leg.mark - long_raw.mark) * 100.0) >= min_credit &&
              long_raw.strike < short_leg.strike &&
              (long_raw.strike - short_leg.strike).abs <= max_spread &&
              (expiration_type.nil? || long_raw.expiration_type == expiration_type) &&
              (settlement_type.nil? || long_raw.settlement_type == settlement_type) &&
              (option_root.nil? || long_raw.option_root == option_root)
          end

          next unless potential_longs.any?

          best_long_raw = potential_longs.min_by(&:mark)
          long_leg = Services::Trades::PutOption.from_schwab_option(
            best_long_raw,
            quantity: quantity
          )

          @trades << Services::Trades::PutSpread.new(
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

