require 'time'
require 'math'

class MarketDataDeltaCalculator
  # Calculate time to expiry from timestamp
  def self.time_to_expiry(timestamp_ns, expiration_date)
    # Convert nanoseconds to seconds
    timestamp_sec = timestamp_ns / 1_000_000_000.0
    current_time = Time.at(timestamp_sec)

    # Calculate days to expiry (including time of day)
    expiry_time = Time.new(expiration_date.year, expiration_date.month, expiration_date.day, 16, 0, 0, '-05:00') # 4pm ET
    days_to_expiry = (expiry_time - current_time) / (24 * 60 * 60)

    # Convert to years
    days_to_expiry / 365.25
  end

  # Main delta calculation using market data
  def self.calculate_delta_from_market_data(option_data, spot_price, risk_free_rate = 0.045)
    option_info = parse_option_ticker(option_data[:ticker])
    return nil unless option_info

    time_to_expiry = time_to_expiry(option_data[:timestamp], option_info[:expiration])
    return nil if time_to_expiry <= 0

    # Use the market price (close price)
    market_price = option_data[:close]

    # Calculate implied volatility from market price
    iv = implied_volatility_from_market(
      market_price: market_price,
      spot_price: spot_price,
      strike_price: option_info[:strike],
      time_to_expiry: time_to_expiry,
      risk_free_rate: risk_free_rate,
      option_type: option_info[:option_type]
    )

    return nil unless iv

    # Calculate delta using market-implied volatility
    delta = calculate_delta_bs(
      spot_price: spot_price,
      strike_price: option_info[:strike],
      time_to_expiry: time_to_expiry,
      risk_free_rate: risk_free_rate,
      volatility: iv,
      option_type: option_info[:option_type]
    )

    {
      delta: delta,
      implied_vol: iv,
      time_to_expiry: time_to_expiry,
      strike: option_info[:strike],
      option_type: option_info[:option_type],
      market_price: market_price
    }
  end

  # Finite difference delta calculation (most reliable for market data)
  def self.calculate_delta_finite_difference(option_data, spot_price, risk_free_rate = 0.045)
    option_info = parse_option_ticker(option_data[:ticker])
    return nil unless option_info

    time_to_expiry = time_to_expiry(option_data[:timestamp], option_info[:expiration])
    return nil if time_to_expiry <= 0

    market_price = option_data[:close]

    # Calculate IV at current spot
    iv = implied_volatility_from_market(
      market_price: market_price,
      spot_price: spot_price,
      strike_price: option_info[:strike],
      time_to_expiry: time_to_expiry,
      risk_free_rate: risk_free_rate,
      option_type: option_info[:option_type]
    )

    return nil unless iv

    # Use finite difference with small bump
    bump = spot_price * 0.005  # 0.5% bump

    price_up = black_scholes_price(
      spot_price + bump, option_info[:strike], time_to_expiry,
      risk_free_rate, iv, option_info[:option_type]
    )

    price_down = black_scholes_price(
      spot_price - bump, option_info[:strike], time_to_expiry,
      risk_free_rate, iv, option_info[:option_type]
    )

    delta = (price_up - price_down) / (2 * bump)

    {
      delta: delta,
      implied_vol: iv,
      method: 'finite_difference',
      bump_size: bump
    }
  end

  private

  # Black-Scholes option pricing
  def self.black_scholes_price(spot, strike, time_to_expiry, risk_free_rate, volatility, option_type)
    d1 = (Math.log(spot / strike) + (risk_free_rate + 0.5 * volatility**2) * time_to_expiry) /
         (volatility * Math.sqrt(time_to_expiry))
    d2 = d1 - volatility * Math.sqrt(time_to_expiry)

    case option_type
    when 'CALL'
      spot * norm_cdf(d1) - strike * Math.exp(-risk_free_rate * time_to_expiry) * norm_cdf(d2)
    when 'PUT'
      strike * Math.exp(-risk_free_rate * time_to_expiry) * norm_cdf(-d2) - spot * norm_cdf(-d1)
    end
  end

  # Black-Scholes delta
  def self.calculate_delta_bs(spot_price:, strike_price:, time_to_expiry:, risk_free_rate:, volatility:, option_type:)
    d1 = (Math.log(spot_price / strike_price) + (risk_free_rate + 0.5 * volatility**2) * time_to_expiry) /
         (volatility * Math.sqrt(time_to_expiry))

    case option_type
    when 'CALL'
      norm_cdf(d1)
    when 'PUT'
      norm_cdf(d1) - 1
    end
  end

  # Implied volatility using Brent's method
  def self.implied_volatility_from_market(market_price:, spot_price:, strike_price:, time_to_expiry:, risk_free_rate:, option_type:)
    # Check for intrinsic value
    intrinsic = case option_type
               when 'CALL'
                 [spot_price - strike_price, 0].max
               when 'PUT'
                 [strike_price - spot_price, 0].max
               end

    # If market price is at intrinsic value, return minimal IV
    return 0.01 if (market_price - intrinsic).abs < 0.01

    objective_function = lambda do |vol|
      price = black_scholes_price(spot_price, strike_price, time_to_expiry, risk_free_rate, vol, option_type)
      price - market_price
    end

    # Use wider bounds for volatile markets
    vol_low = 0.001   # 0.1%
    vol_high = 3.0    # 300%

    f_low = objective_function.call(vol_low)
    f_high = objective_function.call(vol_high)

    # If no root exists in bounds, return nil
    return nil if f_low * f_high > 0

    brent_method(objective_function, vol_low, vol_high, 1e-8)
  end

  # Simplified Brent's method
  def self.brent_method(func, a, b, tolerance, max_iterations = 50)
    fa = func.call(a)
    fb = func.call(b)

    return nil if fa * fb > 0

    (1..max_iterations).each do
      return b if fb.abs < tolerance || (b - a).abs < tolerance

      # Simple bisection (more reliable than full Brent's for this use case)
      c = (a + b) / 2.0
      fc = func.call(c)

      if fa * fc < 0
        b = c
        fb = fc
      else
        a = c
        fa = fc
      end
    end

    b
  end

  # Normal CDF approximation
  def self.norm_cdf(x)
    return 0.0 if x < -10
    return 1.0 if x > 10

    # Abramowitz and Stegun approximation
    sign = x >= 0 ? 1 : -1
    x = x.abs

    a1 =  0.254829592
    a2 = -0.284496736
    a3 =  1.421413741
    a4 = -1.453152027
    a5 =  1.061405429
    p  =  0.3275911

    t = 1.0 / (1.0 + p * x)
    y = 1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * Math.exp(-x * x)

    0.5 * (1.0 + sign * y)
  end
end

option_records = [

]

option_records.each do |record|
  option_data = {
    ticker: record['ticker'],
    close: record['close'].to_f,
    timestamp: record['window_nanosecond_start'].to_i
  }

  # Get corresponding SPX price for this timestamp
  spx_price = get_spx_price_at_timestamp(option_data[:timestamp])

  # Calculate delta
  result = MarketDataDeltaCalculator.calculate_delta_from_market_data(
    option_data,
    spx_price,
    0.045
  )

  if result
    puts "#{option_data[:ticker]} - Delta: #{result[:delta].round(4)}, IV: #{(result[:implied_vol]*100).round(2)}%"
  end
end