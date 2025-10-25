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

      # Smart calculation method that derives missing values from available ones
      # Relationships: mark = extrinsic + intrinsic
      # - intrinsic is calculated from strike and underlying_price (0 for OTM)
      # - If extrinsic is set, mark = extrinsic + intrinsic
      # - If mark is set, extrinsic = mark - intrinsic
      def calculate_values!
        # Now determine mark and extrinsic based on what's set
        if @extrinsic && !@mark
          # We have extrinsic, calculate mark
          @mark = @extrinsic + calc_intrinsic
        elsif @mark && !@extrinsic
          # We have mark, calculate extrinsic
          @extrinsic = @mark - calc_intrinsic
        elsif !@mark && !@extrinsic
          # Neither is set, can't calculate
          # This is okay - they'll remain nil
        end
        # If both are set, leave them as-is

        self
      end

      def mark
        return @mark if @mark

        # Try to calculate if we have extrinsic
        if @extrinsic
          @mark = @extrinsic + calc_intrinsic
        end

        @mark
      end

      def intrinsic
        return @intrinsic if @intrinsic
        @intrinsic = calc_intrinsic
      end

      def extrinsic
        return @extrinsic if @extrinsic

        # Try to calculate if we have mark
        if @mark
          @extrinsic = @mark - calc_intrinsic
        end

        @extrinsic
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

      def calc_intrinsic
        # For OTM options, intrinsic value is 0
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
