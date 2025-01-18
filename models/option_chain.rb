require 'json'
require 'date'
require_relative 'option'

class OptionFilter
  def initialize(attribute:, comparison:, value: nil)
    @attribute = attribute
    @comparison = comparison
    @value = value
  end

  attr_reader :attribute, :comparison, :value

  # opt_value = transform_attribute(opt, attribute)
  # if comparison.respond_to?(:call)
  #   comparison.call(opt_value)
  # else
  #   opt_value.public_send(comparison, value)
  # end

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
    def from_raw(data)
      underlying_symbol = data.fetch(:symbol)

      call_dates = []
      call_opts = []
      data.fetch(:callExpDateMap).each do |exp_date, options|
        call_dates << Date.strptime(exp_date.to_s.split(":").first, "%Y-%m-%d")

        options.each do |_, option_data|
          call_opts << Option.build(underlying_symbol, option_data.first)
        end
      end

      put_dates = []
      put_opts = []
      data.fetch(:putExpDateMap).each do |exp_date, options|
        put_dates << Date.strptime(exp_date.to_s.split(":").first, "%Y-%m-%d")

        options.each do |_, option_data|
          put_opts << Option.build(underlying_symbol, option_data.first)
        end
      end

      new(
        symbol: data.fetch(:symbol),
        status: data.fetch(:status),
        strategy: data.fetch(:strategy),
        interval: data.fetch(:interval),
        is_delayed: data.fetch(:isDelayed),
        is_index: data.fetch(:isIndex),
        interest_rate: data.fetch(:interestRate),
        underlying_price: data.fetch(:underlyingPrice),
        volatility: data.fetch(:volatility),
        days_to_expiration: data.fetch(:daysToExpiration),
        dividend_yield: data.fetch(:dividendYield),
        number_of_contracts: data.fetch(:numberOfContracts),
        asset_main_type: data.fetch(:assetMainType, nil),
        asset_sub_type: data.fetch(:assetSubType, nil),
        is_chain_truncated: data.fetch(:isChainTruncated),
        call_dates: call_dates,
        call_opts: call_opts,
        put_dates: put_dates,
        put_opts: put_opts
      )
    end
  end

  def initialize(
    symbol:, status:, strategy:, interval:, is_delayed:, is_index:, interest_rate:, underlying_price:, volatility:, days_to_expiration:, dividend_yield:, number_of_contracts:, asset_main_type:, asset_sub_type:, is_chain_truncated:, call_dates: [], call_opts: [], put_dates: [], put_opts: []
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
    @dividend_yield = dividend_yield
    @number_of_contracts = number_of_contracts
    @asset_main_type = asset_main_type
    @asset_sub_type = asset_sub_type
    @is_chain_truncated = is_chain_truncated
    @call_dates = call_dates
    @call_opts = call_opts
    @put_dates = put_dates
    @put_opts = put_opts
  end

  attr_reader :symbol, :status, :strategy, :interval, :is_delayed, :is_index, :interest_rate, :underlying_price, :volatility, :days_to_expiration, :dividend_yield, :number_of_contracts, :asset_main_type, :asset_sub_type, :is_chain_truncated, :call_dates, :call_opts, :put_dates, :put_opts

  def filter(put_call: nil, filters: [])
    selected_options =
      case put_call
      when :put
        put_opts
      when :call
        call_opts
      else
        call_opts + put_opts
      end

    filters.each do |filter|
      selected_options = selected_options.select do |opt|
        filter.apply(opt)
      end
    end

    selected_options
  end

  private
end
