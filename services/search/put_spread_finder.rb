require "pry"
require_relative "../../mixins/schwab/schwab"
require_relative "../trades/put_option"
require_relative "../trades/put_spread"

class PutSpreadFinder
  include Schwab

  attr_reader :symbol, :end_date, :short_delta, :max_spread,
    :min_credit, :min_open_interest, :dist_from_strike, :trades, :short_legs,
    :expiration_date, :quantity

  def initialize(
    symbol:,
    end_date: Date.today + 90,
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
    @end_date = end_date
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
    @short_legs = opt_chain.filter(
      put_call: :put,
      filters: short_filters
    )

    short_legs.each do |short_raw|
      short_leg = PutOption.new(
        short_raw.symbol,
        strike: short_raw.strike,
        delta: short_raw.delta,
        mark: short_raw.mark,
        ask: short_raw.ask,
        bid: short_raw.bid,
        expiration_date: short_raw.expiration_date,
        quantity: quantity
      )
      potential_longs = opt_chain.filter(put_call: :put, filters: long_filters(short_leg))

      if potential_longs.any?
        best_long_raw = potential_longs.min_by(&:mark)
        long_leg = PutOption.new(
          best_long_raw.symbol,
          strike: best_long_raw.strike,
          delta: best_long_raw.delta,
          mark: best_long_raw.mark,
          ask: best_long_raw.ask,
          bid: best_long_raw.bid,
          expiration_date: best_long_raw.expiration_date,
          quantity: quantity
        )

        @trades << PutSpread.new(
          short_leg: short_leg,
          long_leg: long_leg
        )
      end
    end

    @trades.max_by(&:credit_debit)
  end

  def opt_chain=(opt_chain)
    @opt_chain = opt_chain
  end

  def opt_chain
    @opt_chain ||= option_chain(
      symbol,
      contract_type: "PUT",
      strike_range: "OTM",
      to_date: end_date,
    )
  end

  def short_filters
    [
      [
        :delta,
        ->(delta) { delta.abs <= short_delta && delta.abs >= 0.00 }
      ],
      [:open_interest, ">", min_open_interest],
      [
        :strike,
        ->(strike) do
          ((@opt_chain.underlying_price - strike) / @opt_chain.underlying_price).abs >= dist_from_strike
        end
      ],
      [
        :mark,
        ->(mark) { mark * 100.0 >= min_credit }
      ]
    ].then do |filters|
      unless expiration_date.nil?
        filters << [:expiration_date, "==", expiration_date]
      else
        filters << [:expiration_date, "<=", end_date]
      end
    end
  end

  def long_filters(short)
    [
      [
        :strike,
        ->(strike) { ((short.strike - max_spread.to_f)..short.strike).cover? strike }
      ],
      [:open_interest, ">", min_open_interest],
      [:expiration_date, "==", short.expiration_date],
      [
        :mark,
        ->(mark) { (short.mark - mark) * 100.0 >= min_credit }
      ],
      [:delta, ->(delta) { delta.abs >= 0.00 && delta.abs <= 1.0 }],
    ]
  end
end
