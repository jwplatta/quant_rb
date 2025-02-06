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

  attr_reader :symbol, :contract_type, :start_date, :end_date, :short_delta, :max_spread, :min_credit, :min_open_interest, :dist_from_strike

  def initialize(
    symbol:,
    contract_type:,
    start_date: Date.today,
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
    @start_date = start_date
    @end_date = end_date
    @short_delta = short_delta
    @max_spread = max_spread
    @min_credit = min_credit
    @min_open_interest = min_open_interest
    @dist_from_strike = dist_from_strike
  end

  def search
    call_put = contract_type.downcase.to_sym
    potential_short_puts = option_chain.filter(put_call: call_put, filters: short_filters)
    trades = []

    potential_short_puts.each do |short_put_raw|
      short_put = Position.new(
        short_put_raw.symbol,
        short_put_raw.underlying_symbol,
        short_put_raw.strike,
        short_put_raw.delta,
        short_put_raw.mark,
        short_put_raw.ask,
        short_put_raw.bid,
        short_put_raw.expiration_date
      )
      potential_long_puts = option_chain.filter(put_call: call_put, filters: long_filters(short_put))

      if potential_long_puts.any?
        best_long_put_raw = potential_long_puts.min_by(&:mark)
        long_put = Position.new(
          best_long_put_raw.symbol,
          best_long_put_raw.underlying_symbol,
          best_long_put_raw.strike,
          best_long_put_raw.delta,
          best_long_put_raw.mark,
          best_long_put_raw.ask,
          best_long_put_raw.bid,
          best_long_put_raw.expiration_date
        )

        trades << PutSpread.new(
          short_leg: short_put,
          long_leg: long_put
        )
      end
    end

    trades
  end

  def short_filters
    [
      OptionFilter.new(
        attribute: :delta,
        comparison: "<=",
        value: short_delta
      ),
      OptionFilter.new(
        attribute: :open_interest,
        comparison: ">",
        value: min_open_interest
      ),
      OptionFilter.new(
        attribute: :strike,
        comparison: ->(strike) { ((option_chain.underlying_price - strike) / option_chain.underlying_price).abs >= dist_from_strike }
      ),
      OptionFilter.new(
        attribute: :mark,
        comparison: ->(mark) { mark * 100.0 >= min_credit }
      )
    ]
  end

  def long_filters(short_put)
    [
      OptionFilter.new(
        attribute: :strike,
        comparison: ->(strike) { ((short_put.strike - max_spread.to_f)...short_put.strike).cover? strike }
      ),
      OptionFilter.new(
        attribute: :open_interest,
        comparison: ">",
        value: min_open_interest
      ),
      OptionFilter.new(
        attribute: :expiration_date,
        comparison: "==",
        value: short_put.expiration_date
      ),
      OptionFilter.new(
        attribute: :mark,
        comparison: ->(mark) { (short_put.mark - mark) * 100.0 >= 100.0 }
      )
    ]
  end

  def option_chain
    return @option_chain if @option_chain

    resp = client.get_option_chain(
      symbol,
      contract_type: contract_type,
      strike_range: "OTM",
      from_date: start_date,
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
