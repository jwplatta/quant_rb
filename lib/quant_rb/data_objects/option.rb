# frozen_string_literal: true

module QuantRb
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
        bid: nil,
        ask: nil,
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
        volatility: nil,
        **kwargs
      )
        @symbol            = symbol
        @underlying_symbol = underlying_symbol
        @strike            = strike
        @put_call          = put_call
        @underlying_price  = underlying_price
        @expiration_date   = expiration_date
        @days_to_expiration = days_to_expiration
        @bid               = bid
        @ask               = ask
        @delta             = delta
        @gamma             = gamma
        @theta             = theta
        @vega              = vega
        @rho               = rho
        @open_interest     = open_interest
        @total_volume      = total_volume
        @expiration_type   = expiration_type
        @settlement_type   = settlement_type
        @option_root       = option_root
        @open              = open
        @high              = high
        @low               = low
        @close             = close
        @intrinsic         = intrinsic
        @extrinsic         = extrinsic
        @timestamp         = timestamp
        @volatility        = volatility

        set_price_values(mark, intrinsic, extrinsic)
      end

      attr_accessor :delta, :gamma, :theta, :vega, :rho, :mark, :intrinsic, :extrinsic, :bid, :ask, :volatility
      attr_reader   :symbol, :underlying_symbol, :strike, :put_call, :underlying_price,
                    :expiration_date, :days_to_expiration, :open_interest, :total_volume,
                    :expiration_type, :settlement_type, :option_root,
                    :open, :high, :low, :close, :timestamp, :volatility

      def call?
        put_call == QuantRb::CALL
      end

      def put?
        put_call == QuantRb::PUT
      end

      def in_the_money?
        return false if underlying_price.nil? || strike.nil?
        call? ? underlying_price > strike : underlying_price < strike
      end

      def out_of_money?
        !in_the_money?
      end

      def mid
        return mark if bid.nil? || ask.nil?
        (bid + ask) / 2.0
      end

      def intrinsic
        return @intrinsic if @intrinsic
        @intrinsic = calc_intrinsic
      end

      def moneyness
        call? ? underlying_price / strike.to_f : strike / underlying_price.to_f
      end

      def to_h
        {
          symbol: symbol,
          underlying_symbol: underlying_symbol,
          strike: strike,
          put_call: put_call,
          underlying_price: underlying_price,
          expiration_date: expiration_date,
          days_to_expiration: days_to_expiration,
          mark: mark,
          bid: bid,
          ask: ask,
          delta: delta,
          gamma: gamma,
          theta: theta,
          vega: vega,
          rho: rho,
          open_interest: open_interest,
          total_volume: total_volume,
          intrinsic: intrinsic,
          extrinsic: extrinsic,
          volatility: volatility
        }
      end

      def self.from_h(h)
        new(**h.transform_keys(&:to_sym))
      end

      private

      def set_price_values(mark_val, intrinsic_val, extrinsic_val)
        if mark_val && !intrinsic_val && !extrinsic_val
          @mark = mark_val
          @extrinsic = mark_val - calc_intrinsic
        elsif intrinsic_val && extrinsic_val && !mark_val
          @intrinsic = intrinsic_val
          @extrinsic = extrinsic_val
          @mark = intrinsic_val + extrinsic_val
        elsif mark_val && intrinsic_val
          @mark = mark_val
          @intrinsic = intrinsic_val
          @extrinsic = mark_val - intrinsic_val
        else
          @mark = mark_val
        end
      end

      def calc_intrinsic
        return 0.0 unless in_the_money?
        raise ArgumentError, "Cannot calculate intrinsic: underlying_price is nil" if underlying_price.nil?

        call? ? underlying_price - strike : strike - underlying_price
      end
    end
  end
end
