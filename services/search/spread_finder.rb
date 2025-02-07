require "pry"
require "dotenv"
require "schwab_rb"
require_relative "../../models/option_chain"
require_relative "../trades/iron_condor"
require_relative "../trades/put_spread"

Dotenv.load

# REVIEW: Need to resolve the shared interface between the Position
# class in models and the Position-like objects that get used in the
# trades classes.
OptionPosition = Struct.new(
  :symbol,
  :underlying_symbol,
  :strike,
  :delta,
  :mark,
  :ask,
  :bid,
  :expiration_date
)

class SpreadFinder
  CONTRACT_TYPES = %w[CALL PUT]

  attr_reader :symbol, :contract_type, :end_date, :short_delta, :max_spread, :min_credit, :min_open_interest, :dist_from_strike

  def initialize(
    symbol:,
    contract_type:,
    end_date: Date.today + 90,
    short_delta: 0.15,
    max_spread: 20.0,
    min_credit: 100.0,
    min_open_interest: 0,
    dist_from_strike: 0.07
  )
    @symbol = symbol

    raise "Invalid spread type" unless CONTRACT_TYPES.include?(contract_type)
    @contract_type = contract_type
    @end_date = end_date
    @short_delta = short_delta
    @max_spread = max_spread
    @min_credit = min_credit
    @min_open_interest = min_open_interest
    @dist_from_strike = dist_from_strike
  end

  def search
    call_put = contract_type.downcase.to_sym

    potential_shorts = option_chain.filter(
      put_call: call_put,
      filters: short_filters
    )
    trades = []

    potential_shorts.each do |short_raw|
      short = OptionPosition.new(
        short_raw.symbol,
        short_raw.underlying_symbol,
        short_raw.strike,
        short_raw.delta,
        short_raw.mark,
        short_raw.ask,
        short_raw.bid,
        short_raw.expiration_date
      )
      potential_longs = option_chain.filter(put_call: call_put, filters: long_filters(short))

      if potential_longs.any?
        best_long_raw = potential_longs.min_by(&:mark)
        long = OptionPosition.new(
          best_long_raw.symbol,
          best_long_raw.underlying_symbol,
          best_long_raw.strike,
          best_long_raw.delta,
          best_long_raw.mark,
          best_long_raw.ask,
          best_long_raw.bid,
          best_long_raw.expiration_date
        )

        trades << PutSpread.new(
          short_leg: short,
          long_leg: long
        )
      end
    end

    trades
  end

  def short_filters
    [
        [:delta, "<=", short_delta],
        [:open_interest, ">", min_open_interest],
        [
          :strike,
          ->(strike) { ((option_chain.underlying_price - strike) / option_chain.underlying_price).abs >= dist_from_strike }
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
          ->(strike) { (short.strike...(short.strike + max_spread.to_f)).cover? strike }
        ],
        [:open_interest, ">", min_open_interest],
        [:expiration_date, "==", short.expiration_date],
        [
          :mark,
          ->(mark) { (short.mark - mark) * 100.0 >= 100.0 }
        ]
      ]
    else
      [
        [
          :strike,
          ->(strike) { ((short.strike - max_spread.to_f)...short.strike).cover? strike }
        ],
        [:open_interest, ">", min_open_interest],
        [:expiration_date, "==", short.expiration_date],
        [
          :mark,
          ->(mark) { (short.mark - mark) * 100.0 >= 100.0 }
        ]
      ]
    end
  end

  def option_chain
    return @option_chain if defined?(@option_chain)

    resp = client.get_option_chain(
      symbol,
      contract_type: contract_type,
      strike_range: "OTM",
      to_date: end_date
    )

    @option_chain = if resp.status == 200
      JSON.parse(resp.body, symbolize_names: true).then do |data|
        OptionChain.build(data)
      end
    else
      raise "Error getting option chain: #{resp.body}"
    end
  end

  private

  def today
    Date.today
  end

  def client
    @client ||= SchwabRb::Auth.init_client_easy(
      ENV["SCHWAB_API_KEY"],
      ENV["SCHWAB_APP_SECRET"],
      ENV["APP_CALLBACK_URL"],
      ENV["TOKEN_PATH"]
    )
  end
end
