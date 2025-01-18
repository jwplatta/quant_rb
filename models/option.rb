require 'json'
require 'date'

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