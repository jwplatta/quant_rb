require 'json'
require 'pry'
require 'date'

class OptionFilter
  def initialize(attribute:, comparison:, value: nil)
    @attribute = attribute
    @comparison = comparison
    @value = value
  end

  def call(option)
    if comparison.respond_to?(:call)
      comparison.call(option.send(attribute))
    else
      option.send(attribute).public_send(comparison, value)
    end
  end
end

class Option
  class << self
    def build(underyling_symbol, data)
      Option.new(
        symbol: data.fetch(:symbol),
        underlying_symbol:  underyling_symbol,
        description: data.fetch(:description),
        strike: data.fetch(:strikePrice),
        put_call: data.fetch(:putCall),
        exchange_name: data.fetch(:exchangeName),
        bid: data.fetch(:bid),
        ask: data.fetch(:ask),
        last: data.fetch(:last),
        mark: data.fetch(:mark),
        bid_size: data.fetch(:bidSize),
        ask_size: data.fetch(:askSize),
        bid_ask_size: data.fetch(:bidAskSize),
        last_size: data.fetch(:lastSize),
        high_price: data.fetch(:highPrice),
        low_price: data.fetch(:lowPrice),
        open_price: data.fetch(:openPrice),
        close_price: data.fetch(:closePrice),
        total_volume: data.fetch(:totalVolume),
        trade_time_in_long: data.fetch(:tradeTimeInLong),
        quote_time_in_long: data.fetch(:quoteTimeInLong),
        net_change: data.fetch(:netChange),
        volatility: data.fetch(:volatility),
        delta: data.fetch(:delta),
        gamma: data.fetch(:gamma),
        theta: data.fetch(:theta),
        vega: data.fetch(:vega),
        rho: data.fetch(:rho),
        open_interest: data.fetch(:openInterest),
        time_value: data.fetch(:timeValue),
        theoretical_option_value: data.fetch(:theoreticalOptionValue),
        theoretical_volatility: data.fetch(:theoreticalVolatility),
        option_deliverables_list: data.fetch(:optionDeliverablesList),
        strike_price: data.fetch(:strikePrice),
        expiration_date: DateTime.parse(data.fetch(:expirationDate)),
        days_to_expiration: data.fetch(:daysToExpiration),
        experiration_type: data.fetch(:expirationType),
        last_trading_day: data.fetch(:lastTradingDay),
        multiplier: data.fetch(:multiplier),
        settlement_type: data.fetch(:settlementType),
        deliverable_note: data.fetch(:deliverableNote),
        percent_change: data.fetch(:percentChange),
        mark_change: data.fetch(:markChange),
        mark_percent_change: data.fetch(:markPercentChange),
        intrinsic_value: data.fetch(:intrinsicValue),
        extrinsic_value: data.fetch(:extrinsicValue),
        option_root: data.fetch(:optionRoot),
        exercise_type: data.fetch(:exerciseType),
        high_52_week: data.fetch(:high52Week),
        low_52_week: data.fetch(:low52Week),
        non_standard: data.fetch(:nonStandard),
        in_the_money: data.fetch(:inTheMoney),
        mini: data.fetch(:mini),
        penny_pilot: data.fetch(:pennyPilot)
      )
    end
  end

  def initialize(
    symbol:, underlying_symbol:, description:, strike:, put_call:,
    exchange_name:, bid:, ask:, last:, mark:, bid_size:, ask_size:,
    bid_ask_size:, last_size:, high_price:, low_price:, open_price:,
    close_price:, total_volume:, trade_time_in_long:,
    quote_time_in_long:, net_change:, volatility:, delta:,
    gamma:, theta:, vega:, rho:, open_interest:, time_value:,
    theoretical_option_value:, theoretical_volatility:, option_deliverables_list:, strike_price:,
    expiration_date:, days_to_expiration:, experiration_type:, last_trading_day:, multiplier:,
    settlement_type:, deliverable_note:, percent_change:, mark_change:, mark_percent_change:, intrinsic_value:, extrinsic_value:, option_root:, exercise_type:, high_52_week:, low_52_week:, non_standard:, in_the_money:, mini:, penny_pilot:
 )
    @symbol = symbol
    @underlying_symbol = underlying_symbol
    @description = description
    @strike = strike
    @put_call = put_call
    @exchange_name = exchange_name
    @bid = bid
    @ask = ask
    @last = last
    @mark = mark
    @bid_size = bid_size
    @ask_size = ask_size
    @bid_ask_size = bid_ask_size
    @last_size = last_size
    @high_price = high_price
    @low_price = low_price
    @open_price = open_price
    @close_price = close_price
    @total_volume = total_volume
    @trade_time_in_long = trade_time_in_long
    @quote_time_in_long = quote_time_in_long
    @net_change = net_change
    @volatility = volatility
    @delta = delta
    @gamma = gamma
    @theta = theta
    @vega = vega
    @rho = rho
    @open_interest = open_interest
    @time_value = time_value
    @theoretical_option_value = theoretical_option_value
    @theoretical_volatility = theoretical_volatility
    @option_deliverables_list = option_deliverables_list
    @strike_price = strike_price
    @expiration_date = expiration_date
    @days_to_expiration = days_to_expiration
    @experiration_type = experiration_type
    @last_trading_day = last_trading_day
    @multiplier = multiplier
    @settlement_type = settlement_type
    @deliverable_note = deliverable_note
    @percent_change = percent_change
    @mark_change = mark_change
    @mark_percent_change = mark_percent_change
    @intrinsic_value = intrinsic_value
    @extrinsic_value = extrinsic_value
    @option_root = option_root
    @exercise_type = exercise_type
    @high_52_week = high_52_week
    @low_52_week = low_52_week
    @non_standard = non_standard
    @in_the_money = in_the_money
    @mini = mini
    @penny_pilot = penny_pilot
  end

  attr_reader :symbol, :underlying_symbol, :description, :strike, :put_call,
    :exchange_name, :bid, :ask, :last, :mark, :bid_size, :ask_size,
    :bid_ask_size, :last_size, :high_price, :low_price, :open_price,
    :close_price, :total_volume, :trade_time_in_long, :quote_time_in_long,
    :net_change, :volatility, :delta, :gamma, :theta, :vega, :rho,
    :open_interest, :time_value, :theoretical_option_value,
    :theoretical_volatility, :option_deliverables_list, :strike_price,
    :expiration_date, :days_to_expiration, :experiration_type, :last_trading_day,
    :multiplier, :settlement_type, :deliverable_note, :percent_change,
    :mark_change, :mark_percent_change, :intrinsic_value, :extrinsic_value,
    :option_root, :exercise_type, :high_52_week, :low_52_week, :non_standard,
    :in_the_money, :mini, :penny_pilot
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
      attribute = filter[:attribute]
      comparison = filter[:comparison]
      value = filter[:value]

      selected_options = selected_options.select do |opt|
        opt_value = transform_attribute(opt, attribute)

        if comparison.respond_to?(:call)
          comparison.call(opt_value)
        else
          opt_value.public_send(comparison, value)
        end
      end
    end

    selected_options
  end

  private

  def transform_attribute(opt, attribute)
    case attribute
    when :delta
      opt.delta.abs
    else
      opt.send(attribute)
    end
  end
end
