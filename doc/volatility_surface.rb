require 'matrix'

class VolatilitySurfaceBuilder

  def initialize
    @surface_cache = {}
    @atm_vol_history = []
  end

  # Build volatility surface from options chain data
  def build_surface_from_chain(timestamp, spot_price, options_chain, risk_free_rate = 0.045)
    surface_data = extract_liquid_options(options_chain, spot_price)
    return nil if surface_data.empty?

    # Group by expiration
    by_expiry = surface_data.group_by { |opt| opt[:expiry] }

    volatility_surface = {}

    by_expiry.each do |expiry, options|
      next if options.length < 3  # Need minimum options for interpolation

      time_to_expiry = calculate_time_to_expiry(timestamp, expiry)
      next if time_to_expiry <= 0

      # Build volatility smile for this expiry
      smile = build_volatility_smile(options, spot_price, time_to_expiry, risk_free_rate)
      next unless smile

      volatility_surface[expiry] = {
        time_to_expiry: time_to_expiry,
        smile: smile,
        atm_vol: smile[:atm_vol]
      }
    end

    # Cache the surface
    @surface_cache[timestamp] = {
      surface: volatility_surface,
      spot: spot_price,
      timestamp: timestamp
    }

    # Track ATM volatility for market regime detection
    atm_vol = calculate_atm_volatility(volatility_surface, spot_price)
    @atm_vol_history << { timestamp: timestamp, atm_vol: atm_vol } if atm_vol

    volatility_surface
  end

  # Get implied volatility for any strike/expiry using the surface
  def get_volatility(strike, expiry, timestamp, spot_price)
    surface = @surface_cache[timestamp]
    return nil unless surface && surface[:surface][expiry]

    smile_data = surface[:surface][expiry][:smile]
    interpolate_volatility_from_smile(strike, smile_data, spot_price)
  end

  # Calculate delta using surface-derived volatility
  def calculate_delta_from_surface(strike, expiry, option_type, timestamp, spot_price, risk_free_rate = 0.045)
    vol = get_volatility(strike, expiry, timestamp, spot_price)
    return nil unless vol

    time_to_expiry = @surface_cache[timestamp][:surface][expiry][:time_to_expiry]

    calculate_black_scholes_delta(
      spot_price: spot_price,
      strike: strike,
      time_to_expiry: time_to_expiry,
      risk_free_rate: risk_free_rate,
      volatility: vol,
      option_type: option_type
    )
  end

  # Detect market volatility regime
  def detect_volatility_regime
    return :unknown if @atm_vol_history.length < 10

    recent_vols = @atm_vol_history.last(20).map { |h| h[:atm_vol] }
    avg_vol = recent_vols.sum / recent_vols.length
    current_vol = recent_vols.last
    vol_trend = (recent_vols.last(5).sum / 5.0) - (recent_vols.first(5).sum / 5.0)

    case
    when current_vol > 0.30
      :high_vol
    when current_vol < 0.15
      :low_vol
    when vol_trend > 0.05
      :vol_expansion
    when vol_trend < -0.05
      :vol_contraction
    else
      :normal
    end
  end

  private

  # Extract liquid options suitable for surface building
  def extract_liquid_options(options_chain, spot_price)
    liquid_options = []

    options_chain.each do |option_data|
      # Parse option details
      option_info = parse_option_ticker(option_data[:ticker])
      next unless option_info

      # Filter for liquid options
      next if option_data[:volume] < 5  # Minimum volume
      next if option_data[:bid].nil? || option_data[:ask].nil?

      bid_ask_spread = option_data[:ask] - option_data[:bid]
      mid_price = (option_data[:bid] + option_data[:ask]) / 2.0

      # Skip if spread too wide
      next if bid_ask_spread / mid_price > 0.30

      # Calculate moneyness
      moneyness = spot_price / option_info[:strike]

      # Focus on tradeable range (0.80 to 1.20 moneyness)
      next if moneyness < 0.80 || moneyness > 1.20

      liquid_options << {
        strike: option_info[:strike],
        expiry: option_info[:expiration],
        option_type: option_info[:option_type],
        mid_price: mid_price,
        volume: option_data[:volume],
        moneyness: moneyness
      }
    end

    liquid_options
  end

  # Build volatility smile for single expiration
  def build_volatility_smile(options, spot_price, time_to_expiry, risk_free_rate)
    call_vols = []
    put_vols = []

    options.each do |option|
      iv = calculate_implied_volatility(
        market_price: option[:mid_price],
        spot_price: spot_price,
        strike: option[:strike],
        time_to_expiry: time_to_expiry,
        risk_free_rate: risk_free_rate,
        option_type: option[:option_type]
      )

      next unless iv && iv > 0.05 && iv < 2.0  # Reasonable bounds

      vol_point = {
        strike: option[:strike],
        moneyness: option[:moneyness],
        volatility: iv,
        volume: option[:volume]
      }

      if option[:option_type] == 'CALL'
        call_vols << vol_point
      else
        put_vols << vol_point
      end
    end

    return nil if call_vols.empty? && put_vols.empty?

    # Find ATM volatility (closest to moneyness = 1.0)
    all_vols = call_vols + put_vols
    atm_vol = all_vols.min_by { |v| (v[:moneyness] - 1.0).abs }[:volatility]

    # Build interpolation points
    vol_points = {}
    all_vols.each do |vol_data|
      strike = vol_data[:strike]
      # Weight by volume for multiple quotes at same strike
      if vol_points[strike]
        total_volume = vol_points[strike][:volume] + vol_data[:volume]
        weighted_vol = (vol_points[strike][:volatility] * vol_points[strike][:volume] +
                       vol_data[:volatility] * vol_data[:volume]) / total_volume
        vol_points[strike] = {
          volatility: weighted_vol,
          volume: total_volume,
          moneyness: vol_data[:moneyness]
        }
      else
        vol_points[strike] = vol_data
      end
    end

    {
      vol_points: vol_points,
      atm_vol: atm_vol,
      spot: spot_price
    }
  end

  # Interpolate volatility from smile
  def interpolate_volatility_from_smile(target_strike, smile_data, spot_price)
    vol_points = smile_data[:vol_points]
    return nil if vol_points.empty?

    # If exact strike exists, use it
    return vol_points[target_strike][:volatility] if vol_points[target_strike]

    # Find surrounding strikes
    strikes = vol_points.keys.sort

    # Find bracketing strikes
    lower_strike = strikes.select { |s| s <= target_strike }.last
    upper_strike = strikes.select { |s| s >= target_strike }.first

    # Handle edge cases
    if lower_strike.nil?
      return vol_points[upper_strike][:volatility]
    elsif upper_strike.nil?
      return vol_points[lower_strike][:volatility]
    elsif lower_strike == upper_strike
      return vol_points[lower_strike][:volatility]
    end

    # Linear interpolation in strike space
    lower_vol = vol_points[lower_strike][:volatility]
    upper_vol = vol_points[upper_strike][:volatility]

    weight = (target_strike - lower_strike) / (upper_strike - lower_strike)
    interpolated_vol = lower_vol + weight * (upper_vol - lower_vol)

    # Apply volatility smile shape adjustments for extreme strikes
    target_moneyness = spot_price / target_strike
    vol_adjustment = smile_adjustment(target_moneyness, smile_data[:atm_vol])

    interpolated_vol * vol_adjustment
  end

  # Volatility smile shape adjustment
  def smile_adjustment(moneyness, atm_vol)
    # Simple volatility smile model (OTM options have higher vol)
    # This models the typical "volatility smile" or "smirk" pattern

    if moneyness < 0.95  # OTM puts (spot below strike)
      # Vol increases as we go further OTM (put skew)
      skew_factor = 1.0 + 0.5 * (0.95 - moneyness)
    elsif moneyness > 1.05  # OTM calls (spot above strike)
      # Vol increases slightly for OTM calls
      skew_factor = 1.0 + 0.2 * (moneyness - 1.05)
    else  # Near ATM
      skew_factor = 1.0
    end

    [[skew_factor, 0.5].max, 2.0].min  # Bound the adjustment
  end

  # Calculate ATM volatility from surface
  def calculate_atm_volatility(surface, spot_price)
    return nil if surface.empty?

    # Find the shortest expiry with good data
    nearest_expiry = surface.keys.min_by { |exp| surface[exp][:time_to_expiry] }
    return nil unless nearest_expiry

    surface[nearest_expiry][:atm_vol]
  end

  # Helper methods (implement these based on your existing code)
  def parse_option_ticker(ticker)
    # Use your existing implementation
    match = ticker.match(/O:([A-Z]+)(\d{6})([CP])(\d{8})/)
    return nil unless match

    symbol = match[1]
    date_str = match[2]
    option_type = match[3] == 'C' ? 'CALL' : 'PUT'
    strike = match[4].to_f / 1000.0

    year = 2000 + date_str[0..1].to_i
    month = date_str[2..3].to_i
    day = date_str[4..5].to_i
    expiration = Date.new(year, month, day)

    {
      underlying_symbol: symbol,
      expiration: expiration,
      option_type: option_type,
      strike: strike
    }
  end

  def calculate_time_to_expiry(timestamp_ns, expiration_date)
    timestamp_sec = timestamp_ns / 1_000_000_000.0
    current_time = Time.at(timestamp_sec)
    expiry_time = Time.new(expiration_date.year, expiration_date.month, expiration_date.day, 16, 0, 0, '-05:00')
    days_to_expiry = (expiry_time - current_time) / (24 * 60 * 60)
    days_to_expiry / 365.25
  end

  def calculate_implied_volatility(market_price:, spot_price:, strike:, time_to_expiry:, risk_free_rate:, option_type:)
    # Use your existing robust IV calculation
    # This should be the Brent's method implementation you already have
    objective_function = lambda do |vol|
      price = black_scholes_price(spot_price, strike, time_to_expiry, risk_free_rate, vol, option_type)
      price - market_price
    end

    vol_low, vol_high = 0.01, 3.0
    f_low = objective_function.call(vol_low)
    f_high = objective_function.call(vol_high)

    return nil if f_low * f_high > 0

    brent_method(objective_function, vol_low, vol_high, 1e-6)
  end

  def black_scholes_price(spot, strike, time_to_expiry, risk_free_rate, volatility, option_type)
    # Your existing BS pricing implementation
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

  def calculate_black_scholes_delta(spot_price:, strike:, time_to_expiry:, risk_free_rate:, volatility:, option_type:)
    d1 = (Math.log(spot_price / strike) + (risk_free_rate + 0.5 * volatility**2) * time_to_expiry) /
         (volatility * Math.sqrt(time_to_expiry))

    case option_type
    when 'CALL'
      norm_cdf(d1)
    when 'PUT'
      norm_cdf(d1) - 1
    end
  end

  def norm_cdf(x)
    # Your existing implementation
    return 0.0 if x < -10
    return 1.0 if x > 10

    sign = x >= 0 ? 1 : -1
    x = x.abs

    a1, a2, a3, a4, a5, p = 0.254829592, -0.284496736, 1.421413741, -1.453152027, 1.061405429, 0.3275911
    t = 1.0 / (1.0 + p * x)
    y = 1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * Math.exp(-x * x)

    0.5 * (1.0 + sign * y)
  end

  def brent_method(func, a, b, tolerance, max_iterations = 50)
    # Your existing Brent's implementation (simplified version is fine)
    fa = func.call(a)
    fb = func.call(b)

    return nil if fa * fb > 0

    (1..max_iterations).each do
      return b if fb.abs < tolerance || (b - a).abs < tolerance

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
end

# Usage Example:
=begin
surface_builder = VolatilitySurfaceBuilder.new

# For each minute of market data
minute_data.each do |timestamp, data|
  spx_price = data[:spx_price]
  options_chain = data[:options_chain]  # All option quotes for this minute

  # Build volatility surface
  surface = surface_builder.build_surface_from_chain(timestamp, spx_price, options_chain)

  next unless surface

  # Now calculate delta for your target option
  target_strike = 6555
  target_expiry = Date.new(2025, 9, 12)

  delta = surface_builder.calculate_delta_from_surface(
    target_strike,
    target_expiry,
    'CALL',
    timestamp,
    spx_price
  )

  if delta
    puts "#{Time.at(timestamp/1_000_000_000)}: Delta = #{delta.round(4)}"
    puts "Market regime: #{surface_builder.detect_volatility_regime}"
  end
end
=end