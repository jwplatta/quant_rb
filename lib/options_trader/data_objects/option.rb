module OptionsTrader
  module DataObjects
    class Option
      def initialize(
        symbol:,
        underlying_symbol:,
        strike:,
        put_call:,
        underlying_price:,
        expiration_date:,
        days_to_expiration: 0,
        mark: nil,
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
        open: nil,
        high: nil,
        low: nil,
        close: nil,
        timestamp: nil,
        intrinsic: nil,
        extrinsic: nil,
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
        @open = open
        @high = high
        @low = low
        @close = close
        @intrinsic = intrinsic
        @extrinsic = extrinsic
        @timestamp = timestamp

        init_price_values(mark, intrinsic, extrinsic)
      end

      attr_accessor :delta, :gamma, :theta, :vega, :rho, :mark, :intrinsic, :extrinsic

      attr_reader :symbol, :underlying_symbol, :strike, :put_call, :underlying_price,
        :expiration_date, :days_to_expiration, :open_interest, :total_volume, :expiration_type,
        :settlement_type, :option_root, :open, :high, :low, :close, :timestamp

      def call?
        put_call == OptionsTrader::CALL
      end

      def put?
        put_call == OptionsTrader::PUT
      end

      def in_the_money?
        return false if underlying_price.nil? || strike.nil?

        if call?
          underlying_price > strike
        else
          underlying_price < strike
        end
      end

      def calc_mark_from_extrinsic(extrinsic_val)
        @extrinsic = extrinsic_val
        @mark = extrinsic_val + intrinsic
      end

      def calc_extrinsic_from_mark(mark_val)
        @mark = mark_val
        @extrinsic = mark_val - intrinsic
      end

      def intrinsic
        return @intrinsic if @intrinsic
        @intrinsic = calc_intrinsic
      end

      def reset_price_values!
        @mark = nil
        @intrinsic = nil
        @extrinsic = nil
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

      private

      def init_price_values(mark_val, intrinsic_val, extrinsic_val)
        if mark_val && !intrinsic_val && !extrinsic_val
          calc_extrinsic_from_mark(mark_val)
        elsif intrinsic_val && extrinsic_val && !mark_val
          @intrinsic = intrinsic_val
          @extrinsic = extrinsic_val
          @mark = intrinsic_val + extrinsic_val
        elsif mark_val && intrinsic_val && !extrinsic_val
          @mark = mark_val
          @intrinsic = intrinsic_val
          @extrinsic = mark_val - intrinsic_val
        elsif mark_val && extrinsic_val && !intrinsic_val
          @mark = mark_val
          @extrinsic = extrinsic_val
          @intrinsic = mark_val - extrinsic_val
        end
      end

      def calc_intrinsic
        unless in_the_money?
          return 0.0
        end

        # For ITM options, calculate based on underlying price and strike
        if underlying_price.nil?
          raise ArgumentError, "Cannot calculate intrinsic value for ITM option: underlying_price is nil"
        end

        if call?
          underlying_price - strike
        else
          strike - underlying_price
        end
      end
    end
  end
end
