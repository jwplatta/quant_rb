module OptionsTrader
  module DataObjects
    class Option
      def initialize(
        symbol:,
        underlying_symbol:,
        strike:,
        put_call:,
        mark:,
        underlying_price:,
        expiration_date:,
        days_to_expiration: 0,
        delta: nil,
        gamma: nil,
        theta: nil,
        vega: nil,
        rho: nil,
        open_interest: 0,
        total_volume: 0,
        expiration_type: nil,
        settlement_type: nil,
        option_root: nil,
        in_the_money: false,
        open: nil,
        high: nil,
        low: nil,
        close: nil,
        timestamp: nil
      )
        @symbol = symbol
        @underlying_symbol = underlying_symbol
        @strike = strike
        @put_call = put_call
        @mark = mark
        @underlying_price = underlying_price
        @expiration_date = expiration_date
        @days_to_expiration = days_to_expiration
        @delta = delta
        @gamma = gamma
        @theta = theta
        @vega = vega
        @rho = rho
        @open_interest = open_interest
        @total_volume = total_volume
        @expiration_type = expiration_type
        @settlement_type = settlement_type
        @option_root = option_root
        @in_the_money = in_the_money
        @open = open
        @high = high
        @low = low
        @close = close
        @timestamp = timestamp
      end

      attr_accessor :delta, :gamma, :theta, :vega, :rho, :mark

      attr_reader :symbol, :underlying_symbol, :strike, :put_call, :underlying_price,
        :expiration_date, :days_to_expiration, :open_interest, :total_volume, :expiration_type,
        :settlement_type, :option_root, :in_the_money, :open, :high, :low, :close, :timestamp
    end
  end
end
