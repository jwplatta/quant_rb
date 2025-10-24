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
        timestamp: nil,
        intrinsic: 0.0,
        extrinsic: 0.0,
        **kwargs
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
        @intrinsic = intrinsic
        @extrinsic = extrinsic
        @timestamp = timestamp
      end

      attr_accessor :delta, :gamma, :theta, :vega, :rho, :mark, :intrinsic, :extrinsic

      attr_reader :symbol, :underlying_symbol, :strike, :put_call, :underlying_price,
        :expiration_date, :days_to_expiration, :open_interest, :total_volume, :expiration_type,
        :settlement_type, :option_root, :in_the_money, :open, :high, :low, :close, :timestamp

      def call?
        put_call == 'CALL'
      end

      def put?
        put_call == 'PUT'
      end

      def moneyness
        if call?
          underlying_price / strike.to_f
        else
          strike / underlying_price.to_f
        end
      end

      def set_feature(name, value)
        @features ||= {}
        @features[name.to_sym] = value

        define_singleton_method(name.to_sym) do
          @features[name.to_sym]
        end
      end

      def features
        @features || {}
      end

      def has_feature?(name)
        @features&.key?(name.to_sym) || false
      end
    end
  end
end
