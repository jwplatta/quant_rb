class QuoteFactory
  def self.build(data)
    symbol, quote_data = data.first

    case quote_data[:assetMainType]
    when "OPTION"
      OptionQuote.new(quote_data)
    when "INDEX"
      IndexQuote.new(quote_data)
    when "EQUITY"
      EquityQuote.new(quote_data)
    else
      raise "Unknown assetMainType: #{quote_data[:assetMainType]}"
    end
  end
end

class OptionQuote
  attr_reader :symbol, :asset_main_type, :realtime, :ssid, :quote_52_week_high, :quote_52_week_low, :quote_ask_price, :quote_ask_size, :quote_bid_price, :quote_bid_size, :quote_close_price, :quote_delta, :quote_gamma, :quote_high_price, :quote_ind_ask_price, :quote_ind_bid_price, :quote_ind_quote_time, :quote_implied_yield, :quote_last_price, :quote_last_size, :quote_low_price, :quote_mark, :quote_mark_change, :quote_mark_percent_change, :quote_money_intrinsic_value, :quote_net_change, :quote_net_percent_change, :quote_open_interest, :quote_open_price, :quote_quote_time, :quote_rho, :quote_security_status, :quote_theoretical_option_value, :quote_theta, :quote_time_value, :quote_total_volume, :quote_trade_time, :quote_underlying_price, :quote_vega, :quote_volatility, :contract_type, :days_to_expiration, :deliverables, :description, :exchange, :exchange_name, :exercise_type, :expiration_day, :expiration_month, :expiration_type, :expiration_year, :is_penny_pilot, :last_trading_day, :multiplier, :settlement_type, :strike_price, :underlying, :underlying_asset_type

  def initialize(data)
    @symbol = data[:symbol]
    @asset_main_type = data[:assetMainType]
    @realtime = data[:realtime]
    @ssid = data[:ssid]
    @quote_52_week_high = data.dig(:quote, :"52WeekHigh")
    @quote_52_week_low = data.dig(:quote, :"52WeekLow")
    @quote_ask_price = data.dig(:quote, :askPrice)
    @quote_ask_size = data.dig(:quote, :askSize)
    @quote_bid_price = data.dig(:quote, :bidPrice)
    @quote_bid_size = data.dig(:quote, :bidSize)
    @quote_close_price = data.dig(:quote, :closePrice)
    @quote_delta = data.dig(:quote, :delta)
    @quote_gamma = data.dig(:quote, :gamma)
    @quote_high_price = data.dig(:quote, :highPrice)
    @quote_ind_ask_price = data.dig(:quote, :indAskPrice)
    @quote_ind_bid_price = data.dig(:quote, :indBidPrice)
    @quote_ind_quote_time = data.dig(:quote, :indQuoteTime)
    @quote_implied_yield = data.dig(:quote, :impliedYield)
    @quote_last_price = data.dig(:quote, :lastPrice)
    @quote_last_size = data.dig(:quote, :lastSize)
    @quote_low_price = data.dig(:quote, :lowPrice)
    @quote_mark = data.dig(:quote, :mark)
    @quote_mark_change = data.dig(:quote, :markChange)
    @quote_mark_percent_change = data.dig(:quote, :markPercentChange)
    @quote_money_intrinsic_value = data.dig(:quote, :moneyIntrinsicValue)
    @quote_net_change = data.dig(:quote, :netChange)
    @quote_net_percent_change = data.dig(:quote, :netPercentChange)
    @quote_open_interest = data.dig(:quote, :openInterest)
    @quote_open_price = data.dig(:quote, :openPrice)
    @quote_quote_time = data.dig(:quote, :quoteTime)
    @quote_rho = data.dig(:quote, :rho)
    @quote_security_status = data.dig(:quote, :securityStatus)
    @quote_theoretical_option_value = data.dig(:quote, :theoreticalOptionValue)
    @quote_theta = data.dig(:quote, :theta)
    @quote_time_value = data.dig(:quote, :timeValue)
    @quote_total_volume = data.dig(:quote, :totalVolume)
    @quote_trade_time = data.dig(:quote, :tradeTime)
    @quote_underlying_price = data.dig(:quote, :underlyingPrice)
    @quote_vega = data.dig(:quote, :vega)
    @quote_volatility = data.dig(:quote, :volatility)
    @contract_type = data.dig(:reference, :contractType)
    @days_to_expiration = data.dig(:reference, :daysToExpiration)
    @deliverables = data.dig(:reference, :deliverables)
    @description = data.dig(:reference, :description)
    @exchange = data.dig(:reference, :exchange)
    @exchange_name = data.dig(:reference, :exchangeName)
    @exercise_type = data.dig(:reference, :exerciseType)
    @expiration_day = data.dig(:reference, :expirationDay)
    @expiration_month = data.dig(:reference, :expirationMonth)
    @expiration_type = data.dig(:reference, :expirationType)
    @expiration_year = data.dig(:reference, :expirationYear)
    @is_penny_pilot = data.dig(:reference, :isPennyPilot)
    @last_trading_day = data.dig(:reference, :lastTradingDay)
    @multiplier = data.dig(:reference, :multiplier)
    @settlement_type = data.dig(:reference, :settlementType)
    @strike_price = data.dig(:reference, :strikePrice)
    @underlying = data.dig(:reference, :underlying)
    @underlying_asset_type = data.dig(:reference, :underlyingAssetType)
  end
end

class IndexQuote
  attr_reader :symbol, :asset_main_type, :realtime, :ssid, :avg_10_days_volume, :avg_1_year_volume, :div_amount, :div_freq, :div_pay_amount, :div_yield, :eps, :fund_leverage_factor, :pe_ratio, :quote_52_week_high, :quote_52_week_low, :quote_close_price, :quote_high_price, :quote_last_price, :quote_low_price, :quote_net_change, :quote_net_percent_change, :quote_open_price, :quote_security_status, :quote_total_volume, :quote_trade_time, :description, :exchange, :exchange_name

  def initialize(data)
    @symbol = data[:symbol]
    @asset_main_type = data[:assetMainType]
    @realtime = data[:realtime]
    @ssid = data[:ssid]
    @avg_10_days_volume = data.dig(:fundamental, :avg10DaysVolume)
    @avg_1_year_volume = data.dig(:fundamental, :avg1YearVolume)
    @div_amount = data.dig(:fundamental, :divAmount)
    @div_freq = data.dig(:fundamental, :divFreq)
    @div_pay_amount = data.dig(:fundamental, :divPayAmount)
    @div_yield = data.dig(:fundamental, :divYield)
    @eps = data.dig(:fundamental, :eps)
    @fund_leverage_factor = data.dig(:fundamental, :fundLeverageFactor)
    @pe_ratio = data.dig(:fundamental, :peRatio)
    @quote_52_week_high = data.dig(:quote, :"52WeekHigh")
    @quote_52_week_low = data.dig(:quote, :"52WeekLow")
    @quote_close_price = data.dig(:quote, :closePrice)
    @quote_high_price = data.dig(:quote, :highPrice)
    @quote_last_price = data.dig(:quote, :lastPrice)
    @quote_low_price = data.dig(:quote, :lowPrice)
    @quote_net_change = data.dig(:quote, :netChange)
    @quote_net_percent_change = data.dig(:quote, :netPercentChange)
    @quote_open_price = data.dig(:quote, :openPrice)
    @quote_security_status = data.dig(:quote, :securityStatus)
    @quote_total_volume = data.dig(:quote, :totalVolume)
    @quote_trade_time = data.dig(:quote, :tradeTime)
    @description = data.dig(:reference, :description)
    @exchange = data.dig(:reference, :exchange)
    @exchange_name = data.dig(:reference, :exchangeName)
  end
end

class EquityQuote
  attr_reader :symbol, :asset_main_type, :asset_sub_type, :quote_type, :realtime, :ssid, :extended_ask_price, :extended_ask_size, :extended_bid_price, :extended_bid_size, :extended_last_price, :extended_last_size, :extended_mark, :extended_quote_time, :extended_total_volume, :extended_trade_time, :avg_10_days_volume, :avg_1_year_volume, :declaration_date, :div_amount, :div_ex_date, :div_freq, :div_pay_amount, :div_pay_date, :div_yield, :eps, :fund_leverage_factor, :last_earnings_date, :next_div_ex_date, :next_div_pay_date, :pe_ratio, :quote_52_week_high, :quote_52_week_low, :quote_ask_mic_id, :quote_ask_price, :quote_ask_size, :quote_ask_time, :quote_bid_mic_id, :quote_bid_price, :quote_bid_size, :quote_bid_time, :quote_close_price, :quote_high_price, :quote_last_mic_id, :quote_last_price, :quote_last_size, :quote_low_price, :quote_mark, :quote_mark_change, :quote_mark_percent_change, :quote_net_change, :quote_net_percent_change, :quote_open_price, :quote_post_market_change, :quote_post_market_percent_change, :quote_quote_time, :quote_security_status, :quote_total_volume, :quote_trade_time, :cusip, :description, :exchange, :exchange_name, :is_hard_to_borrow, :is_shortable, :htb_rate, :market_last_price, :market_last_size, :market_net_change, :market_percent_change, :market_trade_time

  def initialize(data)
    @symbol = data[:symbol]
    @asset_main_type = data[:assetMainType]
    @asset_sub_type = data[:assetSubType]
    @quote_type = data[:quoteType]
    @realtime = data[:realtime]
    @ssid = data[:ssid]
    @extended_ask_price = data.dig(:extended, :askPrice)
    @extended_ask_size = data.dig(:extended, :askSize)
    @extended_bid_price = data.dig(:extended, :bidPrice)
    @extended_bid_size = data.dig(:extended, :bidSize)
    @extended_last_price = data.dig(:extended, :lastPrice)
    @extended_last_size = data.dig(:extended, :lastSize)
    @extended_mark = data.dig(:extended, :mark)
    @extended_quote_time = data.dig(:extended, :quoteTime)
    @extended_total_volume = data.dig(:extended, :totalVolume)
    @extended_trade_time = data.dig(:extended, :tradeTime)
    @avg_10_days_volume = data.dig(:fundamental, :avg10DaysVolume)
    @avg_1_year_volume = data.dig(:fundamental, :avg1YearVolume)
    @declaration_date = data.dig(:fundamental, :declarationDate)
    @div_amount = data.dig(:fundamental, :divAmount)
    @div_ex_date = data.dig(:fundamental, :divExDate)
    @div_freq = data.dig(:fundamental, :divFreq)
    @div_pay_amount = data.dig(:fundamental, :divPayAmount)
    @div_pay_date = data.dig(:fundamental, :divPayDate)
    @div_yield = data.dig(:fundamental, :divYield)
    @eps = data.dig(:fundamental, :eps)
    @fund_leverage_factor = data.dig(:fundamental, :fundLeverageFactor)
    @last_earnings_date = data.dig(:fundamental, :lastEarningsDate)
    @next_div_ex_date = data.dig(:fundamental, :nextDivExDate)
    @next_div_pay_date = data.dig(:fundamental, :nextDivPayDate)
    @pe_ratio = data.dig(:fundamental, :peRatio)
    @quote_52_week_high = data.dig(:quote, :"52WeekHigh")
    @quote_52_week_low = data.dig(:quote, :"52WeekLow")
    @quote_ask_mic_id = data.dig(:quote, :askMICId)
    @quote_ask_price = data.dig(:quote, :askPrice)
    @quote_ask_size = data.dig(:quote, :askSize)
    @quote_ask_time = data.dig(:quote, :askTime)
    @quote_bid_mic_id = data.dig(:quote, :bidMICId)
    @quote_bid_price = data.dig(:quote, :bidPrice)
    @quote_bid_size = data.dig(:quote, :bidSize)
    @quote_bid_time = data.dig(:quote, :bidTime)
    @quote_close_price = data.dig(:quote, :closePrice)
    @quote_high_price = data.dig(:quote, :highPrice)
    @quote_last_mic_id = data.dig(:quote, :lastMICId)
    @quote_last_price = data.dig(:quote, :lastPrice)
    @quote_last_size = data.dig(:quote, :lastSize)
    @quote_low_price = data.dig(:quote, :lowPrice)
    @quote_mark = data.dig(:quote, :mark)
    @quote_mark_change = data.dig(:quote, :markChange)
    @quote_mark_percent_change = data.dig(:quote, :markPercentChange)
    @quote_net_change = data.dig(:quote, :netChange)
    @quote_net_percent_change = data.dig(:quote, :netPercentChange)
    @quote_open_price = data.dig(:quote, :openPrice)
    @quote_post_market_change = data.dig(:quote, :postMarketChange)
    @quote_post_market_percent_change = data.dig(:quote, :postMarketPercentChange)
    @quote_quote_time = data.dig(:quote, :quoteTime)
    @quote_security_status = data.dig(:quote, :securityStatus)
    @quote_total_volume = data.dig(:quote, :totalVolume)
    @quote_trade_time = data.dig(:quote, :tradeTime)
    @cusip = data.dig(:reference, :cusip)
    @description = data.dig(:reference, :description)
    @exchange = data.dig(:reference, :exchange)
    @exchange_name = data.dig(:reference, :exchangeName)
    @is_hard_to_borrow = data.dig(:reference, :isHardToBorrow)
    @is_shortable = data.dig(:reference, :isShortable)
    @htb_rate = data.dig(:reference, :htbRate)
    @market_last_price = data.dig(:regular, :regularMarketLastPrice)
    @market_last_size = data.dig(:regular, :regularMarketLastSize)
    @market_net_change = data.dig(:regular, :regularMarketNetChange)
    @market_percent_change = data.dig(:regular, :regularMarketPercentChange)
    @market_trade_time = data.dig(:regular, :regularMarketTradeTime)
  end
end