# frozen_string_literal: true

module OptionsTrader
  class VerticalSpreadSearch
    include OptionsTrader::Schwab

    attr_reader :underlying_symbol, :put_call, :spreads, :short_legs, :expiration_date, :quantity,
      :expiration_type, :settlement_type, :option_root, :increment

    def initialize(
      underlying_symbol:,
      put_call:,
      expiration_date: nil,
      quantity: 1,
      expiration_type: nil,
      settlement_type: nil,
      option_root: nil,
      increment: 0.01
    )
      @underlying_symbol = underlying_symbol
      @put_call = put_call
      @expiration_date = expiration_date
      @spreads = []
      @short_legs = []
      @quantity = quantity
      @expiration_type = expiration_type
      @settlement_type = settlement_type
      @option_root = option_root
      @increment = increment
    end

    def find(
      opt_chain_or_params = nil,
      from_date: nil,
      to_date: nil,
      return_spreads: false,
      short_delta: 0.15,
      max_spread: 20.0,
      min_credit: nil,
      min_open_interest: 0,
      dist_from_strike: 0.07
    )
      @opt_chain_or_params = opt_chain_or_params
      @from_date = from_date
      @to_date = to_date
      @return_spreads = return_spreads
      @short_delta = short_delta
      @max_spread = max_spread
      @min_credit = min_credit || 0
      @min_open_interest = min_open_interest
      @dist_from_strike = dist_from_strike

      return NullStrategy.new unless expiration_date

      exp_date_str = expiration_date.strftime("%Y-%m-%d")
      date_filtered_options = options_array.select { |opt| option_matches_date?(opt, exp_date_str) }

      date_filtered_options.each do |short_option|
        next unless passes_short_option_filters?(short_option)

        long_options = select_long_legs(date_filtered_options, short_option)

        long_options.each do |long_option|
          spread = build_spread(short_option, long_option)
          @spreads << spread if spread
        end
      end

      return @spreads if @return_spreads

      if @spreads.empty?
        NullStrategy.new
      else
        @spreads.max_by(&:credit)
      end
    end

    private

    def options_array
      @options_array ||= begin
        unless ['PUT', 'CALL'].include?(put_call)
          raise ArgumentError, "Invalid put_call type: #{put_call}. Must be 'PUT' or 'CALL'."
        end

        return [] unless opt_chain

        if put_call == 'PUT'
          opt_chain.put_opts || []
        elsif put_call == 'CALL'
          opt_chain.call_opts || []
        end
      end
    end

    def opt_chain
      @opt_chain ||= if @opt_chain_or_params.nil?
        option_chain(
          underlying_symbol,
          contract_type: put_call,
          from_date: @from_date || expiration_date,
          to_date: @to_date || expiration_date
        )
      elsif @opt_chain_or_params.respond_to?(:put_opts) && put_call == 'PUT'
        @opt_chain_or_params
      elsif @opt_chain_or_params.respond_to?(:call_opts) && put_call == 'CALL'
        @opt_chain_or_params
      else
        raise ArgumentError, "Invalid option chain or parameters provided"
      end
    end

    def option_matches_date?(option, exp_date_str)
      option.expiration_date.strftime("%Y-%m-%d") == exp_date_str
    end

    def passes_short_option_filters?(option)
      return false unless lte_max_delta?(option)
      return false unless gte_min_open_interest?(option)
      return false unless safe_distance_from_market?(option)
      return false unless is_correct_contract_type?(option)

      true
    end

    def lte_max_delta?(option)
      delta = option.delta&.abs || 0.0
      delta <= @short_delta && delta >= 0.0
    end

    def gte_min_open_interest?(option)
      open_interest = option.open_interest || 0
      open_interest >= @min_open_interest
    end

    def safe_distance_from_market?(option)
      underlying_price = opt_chain.underlying_price
      raise "Underlying price must be set for distance filter" unless underlying_price

      strike = option.strike
      return false unless strike

      distance = ((underlying_price - strike) / underlying_price).abs
      distance >= @dist_from_strike
    end

    def is_correct_contract_type?(option)
      return false if expiration_type && option.expiration_type != expiration_type
      return false if settlement_type && option.settlement_type != settlement_type
      return false if option_root && option.option_root != option_root

      true
    end

    def select_long_legs(options_array, short_option)
      short_strike = short_option.strike
      candidates = []

      options_array.each do |long_option|
        long_strike = long_option.strike
        long_mark = long_option.mark

        next unless long_mark.positive?
        next unless valid_spread?(short_strike, long_strike)
        next unless gte_min_credit?(short_option, long_option)
        next unless is_correct_contract_type?(long_option)
        next unless gte_min_open_interest?(long_option)

        candidates << long_option
      end

      candidates
    end

    def valid_spread?(short_strike, long_strike)
      case put_call
      when "CALL"
        long_strike > short_strike && (long_strike - short_strike) <= @max_spread
      when "PUT"
        long_strike < short_strike && (short_strike - long_strike) <= @max_spread
      else
        false
      end
    end

    def gte_min_credit?(short_option, long_option)
      return true if @min_credit <= 0

      short_mark = short_option.mark
      long_mark = long_option.mark
      credit = short_mark - long_mark

      credit * 100 >= @min_credit
    end

    def opts
      @opts ||= if put_call == 'PUT'
        opt_chain.put_opts
      elsif put_call == 'CALL'
        opt_chain.call_opts
      end
    end

    def spread_class
      if put_call == 'PUT'
        PutSpread
      elsif put_call == 'CALL'
        CallSpread
      end
    end

    def option_class
      if put_call == 'PUT'
        PutOption
      elsif put_call == 'CALL'
        CallOption
      end
    end

    def build_spread(short_option, long_option)
      short_leg = option_class.from_schwab_option(short_option, quantity: quantity)
      long_leg = option_class.from_schwab_option(long_option, quantity: quantity)

      spread_class.new(
        underlying_symbol: underlying_symbol,
        increment: increment,
        short_leg: short_leg,
        long_leg: long_leg
      )
    end
  end
end
