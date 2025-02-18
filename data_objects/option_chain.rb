require 'json'
require 'date'
require_relative 'option'

module DataObjects
  class OptionFilter
    def initialize(attribute:, comparison:, value: nil)
      @attribute = attribute
      @comparison = comparison
      @value = value
    end

    attr_reader :attribute, :comparison, :value

    def apply(option)
      transform_attribute(option).then do |opt_val|
        if comparison.respond_to?(:call)
          comparison.call(opt_val)
        else
          opt_val.public_send(comparison, value)
        end
      end
    end

    private

    def transform_attribute(option)
      case attribute
      when :delta
        option.delta.abs
      else
        option.send(attribute)
      end
    end
  end

  class OptionChain
    class << self
      def build(data)
        underlying_symbol = data.fetch(:symbol)

        call_dates = []
        call_opts = []
        data.fetch(:callExpDateMap).each do |exp_date, options|
          call_dates << Date.strptime(exp_date.to_s.split(":").first, "%Y-%m-%d")

          options.each do |_, option_data|
            call_opts << DataObjects::Option.build(underlying_symbol, option_data.first)
          end
        end

        put_dates = []
        put_opts = []
        data.fetch(:putExpDateMap).each do |exp_date, options|
          put_dates << Date.strptime(exp_date.to_s.split(":").first, "%Y-%m-%d")

          options.each do |_, option_data|
            put_opts << DataObjects::Option.build(underlying_symbol, option_data.first)
          end
        end

        new(
          symbol: data.fetch(:symbol),
          status: data.fetch(:status),
          strategy: data.fetch(:strategy),
          interval: data.fetch(:interval, nil),
          is_delayed: data.fetch(:isDelayed, nil),
          is_index: data.fetch(:isIndex, nil),
          interest_rate: data.fetch(:interestRate, nil),
          underlying_price: data.fetch(:underlyingPrice),
          volatility: data.fetch(:volatility, nil),
          days_to_expiration: data.fetch(:daysToExpiration),
          asset_main_type: data.fetch(:assetMainType, nil),
          asset_sub_type: data.fetch(:assetSubType, nil),
          is_chain_truncated: data.fetch(:isChainTruncated, false),
          call_dates: call_dates,
          call_opts: call_opts,
          put_dates: put_dates,
          put_opts: put_opts
        )
      end
    end

    def initialize(
      symbol:, status:, strategy:, interval:, is_delayed:, is_index:, interest_rate:, underlying_price:, volatility:, days_to_expiration:, asset_main_type:, asset_sub_type:, is_chain_truncated:, call_dates: [], call_opts: [], put_dates: [], put_opts: []
    )
      @symbol = symbol
      @status = status
      @strategy = strategy
      @interval = interval
      @is_delayed = is_delayed
      @is_index = is_index
      @interest_rate = interest_rate
      @underlying_price = underlying_price
      @volatility = volatility
      @days_to_expiration = days_to_expiration
      @asset_main_type = asset_main_type
      @asset_sub_type = asset_sub_type
      @is_chain_truncated = is_chain_truncated
      @call_dates = call_dates
      @call_opts = call_opts
      @put_dates = put_dates
      @put_opts = put_opts
    end

    attr_reader :symbol, :status, :strategy, :interval, :is_delayed, :is_index, :interest_rate, :underlying_price, :volatility, :days_to_expiration, :asset_main_type, :asset_sub_type, :is_chain_truncated, :call_dates, :call_opts, :put_dates, :put_opts

    def filter(put_call: nil, filters: [])
      options = filter_by_type(put_call)
      filters = filters.map { |f_args| build_filter(*f_args) }
      options.select { |opt| filters.map { |f| f.apply(opt) }.all? }
      options.select do |opt|
        filters.map { |f| f.apply(opt) }.all?
      end
    end

    def filter_by_type(put_call)
      case put_call
      when :put
        put_opts
      when :call
        call_opts
      else
        call_opts + put_opts
      end
    end

    def to_a(date = nil)
      call_opts.map do |copt|
        [copt.expiration_date.strftime("%Y-%m-%d"), copt.put_call, copt.strike, copt.delta, copt.bid, copt.ask, copt.mark]
      end + put_opts.map do |popt|
        [popt.expiration_date.strftime("%Y-%m-%d"), popt.put_call, popt.strike, popt.delta, popt.bid, popt.ask, popt.mark]
      end
    end

    private

    def build_filter(*args)
      validate_attr(args.first)

      if args.count == 2 && args.last.lambda?
        DataObjects::OptionFilter.new(
          attribute: args.first,
          comparison: args.last
        )
      elsif args.count == 3
        validate_comparison(args[1])

        DataObjects::OptionFilter.new(
          attribute: args.first,
          comparison: args[1],
          value: args.last
        )
      else
        raise ArgumentError, "Invalid filter arguments"
      end
    end

    def validate_attr(attr)
      unless %i[delta open_interest strike mark expiration_date].include?(attr)
        raise ArgumentError, "Invalid filter attribute"
      end
    end

    def validate_comparison(comparison_op)
      unless %w[< > <= >= == !=].include?(comparison_op)
        raise ArgumentError, "Invalid comparison operator"
      end
    end
  end
end
