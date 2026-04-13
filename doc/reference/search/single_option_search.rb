# frozen_string_literal: true

module OptionsTrader
  class SingleOptionSearch
    include Loggable

    attr_reader :underlying_symbol, :put_call, :expiration_date, :quantity,
      :expiration_type, :settlement_type, :option_root, :increment,
      :markets_service

    def initialize(
      markets_service:,
      underlying_symbol:,
      put_call:,
      expiration_date: nil,
      quantity: 1,
      expiration_type: nil,
      settlement_type: nil,
      option_root: nil,
      increment: 0.01
    )
      @markets_service = markets_service
      @underlying_symbol = underlying_symbol
      @put_call = put_call
      @expiration_date = expiration_date
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
      max_delta: 0.15,
      min_open_interest: 0,
      min_volume: 0,
      dist_from_strike: 0.07,
      return_all: false
    )
      @opt_chain_or_params = opt_chain_or_params
      @from_date = from_date
      @to_date = to_date
      @max_delta = max_delta
      @min_open_interest = min_open_interest
      @min_volume = min_volume
      @dist_from_strike = dist_from_strike
      @return_all = return_all

      return NullStrategy.new unless expiration_date

      exp_date_str = expiration_date.strftime("%Y-%m-%d")
      date_filtered_options = options_array.select { |opt| option_matches_date?(opt, exp_date_str) }

      filtered_options = date_filtered_options.select { |option| passes_option_filters?(option) }

      if @return_all
        filtered_options.map { |option| build_option(option) }
      elsif filtered_options.empty?
        NullStrategy.new
      else
        best_option = find_best_option(filtered_options)
        build_option(best_option)
      end
    end

    private

    def options_array
      @options_array ||= begin
        unless [OptionsTrader::PUT, OptionsTrader::CALL].include?(put_call)
          raise ArgumentError, "Invalid put_call type: #{put_call}. Must be '#{OptionsTrader::PUT}' or '#{OptionsTrader::CALL}'."
        end

        return [] unless opt_chain

        if put_call == OptionsTrader::PUT
          opt_chain.put_opts || []
        elsif put_call == OptionsTrader::CALL
          opt_chain.call_opts || []
        end
      end
    end

    def opt_chain
      @opt_chain ||= if @opt_chain_or_params.nil?
        markets_service.get_option_chain(
          underlying_symbol,
          contract_type: put_call,
          from_date: @from_date || expiration_date,
          to_date: @to_date || expiration_date
        )
      elsif @opt_chain_or_params.respond_to?(:put_opts) && put_call == OptionsTrader::PUT
        @opt_chain_or_params
      elsif @opt_chain_or_params.respond_to?(:call_opts) && put_call == OptionsTrader::CALL
        @opt_chain_or_params
      else
        raise ArgumentError, "Invalid option chain or parameters provided"
      end
    end

    def option_matches_date?(option, exp_date_str)
      option.expiration_date.strftime("%Y-%m-%d") == exp_date_str
    end

    def passes_option_filters?(option)
      return false unless lte_max_delta?(option)
      return false unless gte_min_open_interest?(option)
      return false unless gte_min_volume?(option)
      return false unless safe_distance_from_market?(option)
      return false unless is_correct_contract_type?(option)
      return false unless has_valid_mark?(option)

      true
    end

    def lte_max_delta?(option)
      delta = option.delta&.abs || 0.0
      delta <= @max_delta && delta >= 0.0
    end

    def gte_min_open_interest?(option)
      open_interest = option.open_interest || 0
      open_interest >= @min_open_interest
    end

    def gte_min_volume?(option)
      volume = option.total_volume || 0
      volume >= @min_volume
    end

    def safe_distance_from_market?(option)
      return true if @dist_from_strike <= 0

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

    def has_valid_mark?(option)
      mark = option.mark
      mark && mark > 0
    end

    def find_best_option(options)
      options.max_by { |option| option.mark || 0 }
    end

    def option_class
      if put_call == OptionsTrader::PUT
        PutOption
      elsif put_call == OptionsTrader::CALL
        CallOption
      end
    end

    def build_option(schwab_option)
      option_class.from_schwab_option(schwab_option, quantity: quantity)
    end
  end
end
