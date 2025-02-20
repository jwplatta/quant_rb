require "pry"
require "schwab_rb"
require_relative "../../data_objects/option_chain"
require_relative "../trades/put_spread"

Dotenv.load

# REVIEW: Need to resolve the shared interface between the Position
# class in models and the Position-like objects that get used in the
# trades classes.
TradeLeg = Struct.new(
  :put_call,
  :symbol,
  :underlying_symbol,
  :strike,
  :delta,
  :mark,
  :ask,
  :bid,
  :expiration_date,
  :instruction
)

class SpreadFinder
  CONTRACT_TYPES = %w[CALL PUT]

  attr_reader :symbol, :contract_type, :end_date, :short_delta, :max_spread,
    :min_credit, :min_open_interest, :dist_from_strike, :trades, :short_legs, :option_chain

  def initialize(
    symbol:,
    contract_type:,
    end_date: Date.today + 90,
    short_delta: 0.15,
    max_spread: 20.0,
    min_credit: 100.0,
    min_open_interest: 0,
    dist_from_strike: 0.07,
    option_chain: nil
  )
    @symbol = symbol

    raise "Option chain must be provided" unless option_chain
    raise "Invalid spread type" unless CONTRACT_TYPES.include?(contract_type)

    @contract_type = contract_type
    @end_date = end_date
    @short_delta = short_delta
    @max_spread = max_spread
    @min_credit = min_credit
    @min_open_interest = min_open_interest
    @dist_from_strike = dist_from_strike
    @trades = []
    @short_legs = []
    @option_chain = option_chain
  end

  def search
    put_call = contract_type.downcase.to_sym

    @short_legs = option_chain.filter(
      put_call: put_call,
      filters: short_filters
    )

    short_legs.each do |short_raw|
      short = TradeLeg.new(
        put_call,
        short_raw.symbol,
        short_raw.underlying_symbol,
        short_raw.strike,
        short_raw.delta,
        short_raw.mark,
        short_raw.ask,
        short_raw.bid,
        short_raw.expiration_date,
        "SELL_TO_OPEN"
      )
      potential_longs = option_chain.filter(put_call: put_call, filters: long_filters(short))

      if potential_longs.any?
        best_long_raw = potential_longs.min_by(&:mark)
        long = TradeLeg.new(
          put_call,
          best_long_raw.symbol,
          best_long_raw.underlying_symbol,
          best_long_raw.strike,
          best_long_raw.delta,
          best_long_raw.mark,
          best_long_raw.ask,
          best_long_raw.bid,
          best_long_raw.expiration_date,
          "BUY_TO_OPEN"
        )

        @trades << PutSpread.new(
          short_leg: short,
          long_leg: long
        )
      end
    end

    @trades.max_by(&:credit_debit)
  end

  def short_filters
    [
      [
        :delta,
        ->(delta) { delta.abs <= short_delta }
      ],
      [
        :strike,
        ->(strike) do
          ((option_chain.underlying_price - strike) / option_chain.underlying_price).abs >= dist_from_strike
        end
      ],
      [
        :mark,
        ->(mark) { mark * 100.0 >= min_credit }
      ]
    ]
  end

  def long_filters(short)
    if contract_type == "CALL"
      [
        [
          :strike,
          ->(strike) { (short.strike..(short.strike + max_spread.to_f)).cover? strike }
        ],
        [:expiration_date, "==", short.expiration_date],
        [
          :mark,
          ->(mark) { (short.mark - mark) * 100.0 >= min_credit }
        ]
      ]
    else
      [
        [
          :strike,
          ->(strike) { ((short.strike - max_spread.to_f)..short.strike).cover? strike }
        ],
        [:expiration_date, "==", short.expiration_date],
        [
          :mark,
          ->(mark) { (short.mark - mark) * 100.0 >= min_credit }
        ]
      ]
    end
  end
end
