def cumulative_normal_distribution(x)
  # Approximation of the cumulative standard normal distribution
  0.5 * (1 + Math.erf(x / Math.sqrt(2)))
end

def vix_to_base_volatility(vix_level)
  vix_level / 100.0  # Convert VIX 20 to 0.20 (20%)
end

def volatility_skew_adjustment(strike, spot_price, days_to_expiry)
  moneyness = strike / spot_price
  log_moneyness = Math.log(moneyness)

  skew_slope = -0.15      # Negative skew (puts > calls)
  skew_curvature = 0.02   # Smile curvature

  # Time decay of skew (shorter expiry = more skew)
  time_factor = Math.exp(-days_to_expiry / 30.0)

  # Calculate skew adjustment
  linear_term = skew_slope * log_moneyness * time_factor
  quadratic_term = skew_curvature * (log_moneyness ** 2) * time_factor

  skew_adjustment = linear_term + quadratic_term

  # Return multiplicative factor
  Math.exp(skew_adjustment)
end

def volatility_term_structure(vix_volatility, days_to_expiry)
  # VIX represents 30-day vol, adjust for other timeframes
  target_days = days_to_expiry
  base_days = 30

  case target_days
  when 0..7     # Weekly options
    vix_volatility * 1.15  # Higher vol for short-term
  when 7..21    # Short-term
    vix_volatility * 1.05
  when 21..45   # Near VIX timeframe
    vix_volatility * 1.0   # Use VIX directly
  when 45..90   # Quarterly
    vix_volatility * 0.95
  when 90..180  # Medium-term
    vix_volatility * 0.90
  else          # LEAPS
    vix_volatility * 0.85
  end
end

def estimate_implied_volatility(vix_level, strike, spot_price, days_to_expiry)
  # Step 1: Convert VIX to base volatility
  base_vol = vix_to_base_volatility(vix_level)

  # Step 2: Apply term structure
  term_adjusted_vol = volatility_term_structure(base_vol, days_to_expiry)

  # Step 3: Apply volatility skew
  skew_factor = volatility_skew_adjustment(strike, spot_price, days_to_expiry)

  # Final implied volatility
  implied_vol = term_adjusted_vol * skew_factor

  # Apply reasonable bounds
  [implied_vol, 0.05].max  # Minimum 5% vol
end


def black_scholes_price(spot, strike, time_to_expiry, rate, volatility, option_type)
  # Calculate d1 and d2
  d1 = (Math.log(spot / strike) + (rate + 0.5 * volatility**2) * time_to_expiry) / (volatility * Math.sqrt(time_to_expiry))

  d2 = d1 - volatility * Math.sqrt(time_to_expiry)

  # Calculate option price based on type
  case option_type.downcase
  when 'call'
    call_price(spot, strike, time_to_expiry, rate, d1, d2)
  when 'put'
    put_price(spot, strike, time_to_expiry, rate, d1, d2)
  end
end

def call_price(spot, strike, time_to_expiry, rate, d1, d2)
  spot * cumulative_normal_distribution(d1) -
  strike * Math.exp(-rate * time_to_expiry) * cumulative_normal_distribution(d2)
end

def put_price(spot, strike, time_to_expiry, rate, d1, d2)
  strike * Math.exp(-rate * time_to_expiry) * cumulative_normal_distribution(-d2) -
  spot * cumulative_normal_distribution(-d1)
end

contract_type = 'call'
spot_price = 6389.45
strike_price = 6410
days_to_expiry = 3
time_to_expiry = days_to_expiry / 365.0
risk_free_rate = 0.04133
# VIX9D_level = 12.86
VIX_level = 15.15 * 0.5
vix_volatility = estimate_implied_volatility(VIX_level, strike_price, spot_price, days_to_expiry)
puts "Estimated Implied Volatility: #{vix_volatility.round(4)}"
volatility = 0.06695
# volatility = vix_volatility

if contract_type.downcase == 'call'
  puts "Calculating call option price..."
  call_price = black_scholes_price(spot_price, strike_price, time_to_expiry, risk_free_rate, volatility, 'call')
  puts "Call Price: $#{call_price.round(2)}"
elsif contract_type.downcase == 'put'
  puts "Calculating put option price..."
  put_price = black_scholes_price(spot_price, strike_price, time_to_expiry, risk_free_rate, volatility, 'put')
  puts "Put Price: $#{put_price.round(2)}"
else
  raise ArgumentError, "Invalid option type: #{contract_type}. Must be 'call' or 'put'."
end
