# frozen_string_literal: true

require_relative 'schwab'

module Platypi
  module Quoteable
    include Schwab

    attr_accessor :last_quote, :strike, :delta, :mark, :ask, :bid, :expiration_date, :open_interest

    def self.included(base)
      base.class_eval do
        def initialize(*args)
          super(*args) if defined?(super)
          @last_quote = nil
          @strike = nil
          @delta = 999
          @mark = nil
          @ask = nil
          @bid = nil
          @expiration_date = nil
          @open_interest = nil
        end
      end
    end

    def market_change?
      return false unless @last_quote

      old_mark = @last_quote.mark
      check_market
      return false unless old_mark && @mark

      ((@mark - old_mark).abs / old_mark.to_f) > 0.05
    end

    def check_market
      @last_quote = quote(symbol)

      if @last_quote
        @strike = @last_quote.strike_price
        @delta = @last_quote.delta&.abs || 999
        @mark = @last_quote.mark
        @ask = @last_quote.ask_price
        @bid = @last_quote.bid_price
        @expiration_date = Date.new(
          @last_quote.expiration_year,
          @last_quote.expiration_month,
          @last_quote.expiration_day
        )
        @open_interest = @last_quote.open_interest
      end
    rescue StandardError => e
      puts "Error fetching quote for #{symbol}: #{e.message}"
    end
  end
end
