require "pry"
require "dotenv"
require "schwab_rb"
require_relative "../../models/option_chain"

Dotenv.load

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

    potential_short_puts.each do |short_put|
      potential_long_puts = option_chain.filter(put_call: call_put, filters: long_filters(short_put))

      if potential_long_puts.any?
        best_long_put = potential_long_puts.min_by(&:mark)
        trade_cnt += 1

        trades << [
          trade_cnt,
          ticker,
          option_chain.underlying_price.round(3),
          short_put.expiration_date.strftime('%Y-%m-%d'),
          short_put.days_to_expiration,
          "SELL",
          short_put.strike,
          short_put.delta,
          short_put.bid,
          short_put.ask,
          short_put.mark
        ]

        trades << [
          trade_cnt,
          "",
          "",
          "",
          "",
          "BUY",
          best_long_put.strike,
          best_long_put.delta,
          best_long_put.bid,
          best_long_put.ask,
          best_long_put.mark
        ]
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
    @option_chain ||= client.get_option_chain(
      symbol,
      contract_type: contract_type,
      strike_range: "OTM",
      from_date: start_date,
      to_date: end_date
    ).then do |resp|
      if resp.status == 200
        JSON.parse(resp.body, symbolize_names: true)
      else
        raise "Error getting option chain: #{resp.body}"
      end
    end.then do |data|
      OptionChain.build(data)
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
