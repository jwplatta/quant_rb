# frozen_string_literal: true

require_relative 'schwab/schwab'

module Quoteable
  include Schwab

  def check_market
    quote(symbol).then do |q|
      @delta = q.delta.abs
      @mark = q.mark
      @ask = q.ask_price
      @bid = q.bid_price
      @strike = q.strike_price
      @expiration_date = Date.new(
        q.expiration_year,
        q.expiration_month,
        q.expiration_day
      )
    end
  end
end
