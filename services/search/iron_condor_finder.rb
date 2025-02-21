require "pry"
require "dotenv"
require "schwab_rb"
require_relative "../trades/iron_condor"
require_relative "../trades/put_spread"
require_relative "spread_finder"

Dotenv.load

class IronCondorFinder
  attr_reader :symbol, :end_date, :short_delta, :max_spread,
    :min_credit, :min_open_interest, :dist_from_strike, :option_chain,
    :call_spread, :put_spread

    def initialize(
      symbol:,
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

    @end_date = end_date
    @short_delta = short_delta
    @max_spread = max_spread
    @min_credit = min_credit
    @min_open_interest = min_open_interest
    @dist_from_strike = dist_from_strike
    @trades = []
    @option_chain = option_chain
    @call_spread = nil
    @put_spread = nil
  end

  def credit_debit
    call_spread.credit_debit + put_spread.credit_debit
  end

  def search
    @call_spread = call_spread_finder.search
    @put_spread = put_spread_finder.search
  end

  def call_spread_finder
    @call_spread_finder ||= spread_finder.new(
      symbol: symbol,
      contract_type: "CALL",
      end_date: end_date,
      short_delta: short_delta,
      max_spread: max_spread,
      min_credit: min_credit,
      min_open_interest: min_open_interest,
      dist_from_strike: dist_from_strike,
      option_chain: option_chain
    )
  end

  def put_spread_finder
    @put_spread_finder ||= spread_finder.new(
      symbol: symbol,
      contract_type: "PUT",
      end_date: end_date,
      short_delta: short_delta,
      max_spread: max_spread,
      min_credit: min_credit,
      min_open_interest: min_open_interest,
      dist_from_strike: dist_from_strike,
      option_chain: option_chain
    )
  end

  private

  def spread_finder
    SpreadFinder
  end
end
