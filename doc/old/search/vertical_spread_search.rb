# frozen_string_literal: true

module OptionsTrader
  class VerticalSpreadSearch
    include Loggable

    attr_reader :underlying_symbol, :contract_type, :expiration_date,
      :expiration_type, :settlement_type, :option_root, :spreads, :short_legs,
      :max_delta, :max_strike, :max_spread, :min_credit, :min_open_interest

    def initialize(
      underlying_symbol:,
      option_root:,
      contract_type:,
      expiration_date: nil,
      expiration_type: nil,
      settlement_type: nil,
      max_delta: 0.15,
      max_strike: nil,
      max_spread: 20.0,
      min_credit: 0,
      min_open_interest: 0
    )
      @underlying_symbol = underlying_symbol
      @option_root = option_root
      @contract_type = contract_type
      @expiration_date = expiration_date
      @expiration_type = expiration_type
      @settlement_type = settlement_type
      @max_delta = max_delta
      @max_strike = max_strike
      @max_spread = max_spread
      @min_credit = min_credit
      @min_open_interest = min_open_interest
      @spreads = []
      @short_legs = []
    end

    # NOTE: returns an array of strategies or a single strategy or NullStrategy
    def find(option_chain)
      short_legs = []

      set_options(option_chain)

      short_legs.each do |short_leg|
        next unless passes_short_option_filters?(short_leg)

        short_legs << short_leg

        candidates = select_candidates(short_leg, option_chain)
        next if candidates.empty?

        long_options = select_long_legs(candidates, short_leg, option_chain)
        next if long_options.empty?

        long_options.each do |long_option|
          # spread = build_spread(short_option, long_option)
          @spreads << [short_option, long_option] if spread
        end
      end

      if @spreads.any?
        @spreads
      else
        NullStrategy.new
      end
    end

    private

    def set_options(option_chain)
      @options ||= if contract_type == OptionsTrader::PUT
        option_chain.put_opts
      elsif contract_type == OptionsTrader::CALL
        option_chain.call_opts
      else
        []
      end
    end

    def short_legs
      @short_legs ||= @options.select do |opt|
        option_matches_date?(opt, expiration_date_to_s) &&
          is_correct_contract_type?(opt) &&
          passes_short_option_filters?(opt)
      end
    end

    def select_candidates(short_leg, option_chain)
      if contract_type == OptionsTrader::CALL
        search_space(option_chain).select { |opt| opt.strike > short_leg.strike }
      else
        search_space(option_chain).select { |opt| opt.strike < short_leg.strike }
      end
    end

    def expiration_date_to_s
      @expiration_date.strftime("%Y-%m-%d")
    end

    def search_space(option_chain)
      @search_space ||= if contract_type == OptionsTrader::CALL
        options_array.select do |opt|
          option_matches_date?(opt, expiration_date_to_s) \
            && opt.strike <= option_chain.underlying_price + option_chain.underlying_price * 0.30 \
            && is_correct_contract_type?(opt)
        end
      elsif contract_type == OptionsTrader::PUT
        options_array.select do |opt|
          option_matches_date?(opt, expiration_date_to_s) \
            && is_correct_contract_type?(opt) \
            && opt.strike >= option_chain.underlying_price - option_chain.underlying_price * 0.30 \
        end
      end
    end

    def options_array
      @options_array ||= begin
        unless [OptionsTrader::PUT, OptionsTrader::CALL].include?(contract_type)
          raise ArgumentError, "Invalid contract_type type: #{contract_type}. Must be OptionsTrader::PUT or OptionsTrader::CALL."
        end

        return [] unless opt_chain

        if contract_type == OptionsTrader::PUT
          opt_chain.put_opts || []
        elsif contract_type == OptionsTrader::CALL
          opt_chain.call_opts || []
        end
      end
    end

    def option_matches_date?(option, exp_date_str)
      option.expiration_date.strftime("%Y-%m-%d") == exp_date_str
    end

    def passes_short_option_filters?(option)
      return false unless lte_max_delta?(option)
      return false unless gte_min_open_interest?(option)

      true
    end

    def lte_max_delta?(option)
      delta = option.delta&.abs || 0.0
      delta <= max_delta && delta >= 0.0
    end

    def gte_min_open_interest?(option)
      open_interest = option.open_interest || 0
      open_interest >= @min_open_interest
    end

    def is_correct_contract_type?(option)
      return false if expiration_type && option.expiration_type != expiration_type
      return false if settlement_type && option.settlement_type != settlement_type
      return false if option.option_root != option_root

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
        next unless gte_min_open_interest?(long_option)

        candidates << long_option
      end

      candidates
    end

    def valid_spread?(short_strike, long_strike)
      case contract_type
      when OptionsTrader::CALL
        long_strike > short_strike && (long_strike - short_strike) <= @max_spread
      when OptionsTrader::PUT
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

    def options
      @options ||= if contract_type == OptionsTrader::PUT
        opt_chain.put_opts
      elsif contract_type == OptionsTrader::CALL
        opt_chain.call_opts
      end
    end

    def option_class
      if contract_type == OptionsTrader::PUT
        PutOption
      elsif contract_type == OptionsTrader::CALL
        CallOption
      end
    end

    def build_spread(short_option, long_option)
      short_leg = option_class.from_schwab_option(short_option)
      long_leg = option_class.from_schwab_option(long_option)

      OptionsTrader::Strategies::VerticalSpread.new(
        short_leg: short_leg,
        long_leg: long_leg,
        contract_type: contract_type
      )
    end
  end
end
