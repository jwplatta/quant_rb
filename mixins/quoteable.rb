# frozen_string_literal: true

require_relative 'schwab/schwab'

module Quoteable
  include Schwab

  def initialize_quoteable
    @quote = nil
  end

  def strike
    @quote&.strike_price
  end

  def delta
    @quote&.delta&.abs
  end

  def mark
    @quote&.mark
  end

  def ask
    @quote&.ask_price
  end

  def bid
    @quote&.bid_price
  end

  def expiration_date
    @expiration_date || Date.new(
      @quote&.expiration_year,
      @quote&.expiration_month,
      @quote&.expiration_day
    )
  end

  def check_market
    @quote = quote(symbol)
  catch StandardError => e
    puts "Error fetching quote for #{symbol}: #{e.message}"
  end
end