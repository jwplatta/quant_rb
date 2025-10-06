#!/usr/bin/env ruby

require 'pry'
require 'date'
require_relative '../config/environment'
require_relative '../lib/options_trader'
require_relative '../lib/options_trader/charts/compare_deltas'

class VolatilitySurfaceBuilder
  def initialize
    @surface_cache = {}
    @atm_vol_history = []
  end

  def build_surface_from_chain(timestamp, spot_price, options_chain, risk_free_rate = 0.045)
    surface_data = extract_liquid_options(options_chain, spot_price)
    return nil if surface_data.empty?

    by_expiry = surface_data.group_by { |opt| opt[:expiry] }
    volatility_surface = {}

    by_expiry.each do |expiry, options|
      next if options.length < 3

      time_to_expiry = calculate_time_to_expiry(timestamp, expiry)
      next if time_to_expiry <= 0

      smile = build_volatility_smile(options, spot_price, time_to_expiry, risk_free_rate)
      next unless smile

      volatility_surface[expiry] = {
        time_to_expiry: time_to_expiry,
        smile: smile,
        atm_vol: smile[:atm_vol]
      }
    end

    @surface_cache[timestamp] = {
      surface: volatility_surface,
      spot: spot_price,
      timestamp: timestamp
    }

    atm_vol = calculate_atm_volatility(volatility_surface, spot_price)
    @atm_vol_history << { timestamp: timestamp, atm_vol: atm_vol } if atm_vol

    volatility_surface
  end

  def get_volatility(strike, expiry, timestamp, spot_price)
    surface = @surface_cache[timestamp]
    return nil unless surface && surface[:surface][expiry]

    smile_data = surface[:surface][expiry][:smile]
    interpolate_volatility_from_smile(strike, smile_data, spot_price)
  end

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

  def extract_liquid_options(options_chain, spot_price)
    liquid_options = []
    all_options = options_chain.call_opts + options_chain.put_opts

    all_options.each do |option|
      next if option.total_volume < 10
      next if option.mark.nil? || option.mark <= 0

      moneyness = spot_price / option.strike
      next if moneyness < 0.8 || moneyness > 1.2

      liquid_options << {
        strike: option.strike,
        expiry: option.expiration_date,
        option_type: option.put_call,
        mid_price: option.mark,
        volume: option.total_volume,
        moneyness: moneyness
      }
    end

    liquid_options
  end

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

      # iv = 0.001 if iv.nil?

      next unless iv && iv > 0.05 && iv < 2.0

      vol_point = {
        strike: option[:strike],
        moneyness: option[:moneyness],
        volatility: iv,
        volume: option[:volume],
        option_type: option[:option_type]
      }

      if option[:option_type].upcase == 'CALL'
        call_vols << vol_point
      else
        put_vols << vol_point
      end
    end

    return nil if call_vols.empty? && put_vols.empty?

    all_vols = call_vols + put_vols
    atm_vol = all_vols.min_by { |v| (v[:moneyness] - 1.0).abs }[:volatility]

    # Combine all volatility points into single structure
    vol_points = {}
    all_vols.each do |vol_data|
      strike = vol_data[:strike]
      if vol_points[strike]
        # If we have both call and put at same strike, volume-weight them
        total_volume = vol_points[strike][:volume] + vol_data[:volume]
        weighted_vol = (vol_points[strike][:volatility] * vol_points[strike][:volume] +
                       vol_data[:volatility] * vol_data[:volume]) / total_volume
        vol_points[strike] = {
          volatility: weighted_vol,
          volume: total_volume,
          moneyness: vol_data[:moneyness],
          option_type: 'COMBINED' # Indicate this is a combined point
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

  def interpolate_volatility_from_smile(target_strike, smile_data, spot_price)
    vol_points = smile_data[:vol_points]
    return nil if vol_points.empty?

    # Check if we have exact match
    return vol_points[target_strike][:volatility] if vol_points[target_strike]

    strikes = vol_points.keys.sort
    lower_strike = strikes.select { |s| s <= target_strike }.last
    upper_strike = strikes.select { |s| s >= target_strike }.first

    if lower_strike.nil?
      return vol_points[upper_strike][:volatility]
    elsif upper_strike.nil?
      return vol_points[lower_strike][:volatility]
    elsif lower_strike == upper_strike
      return vol_points[lower_strike][:volatility]
    end

    lower_vol = vol_points[lower_strike][:volatility]
    upper_vol = vol_points[upper_strike][:volatility]

    weight = (target_strike - lower_strike) / (upper_strike - lower_strike)
    interpolated_vol = lower_vol + weight * (upper_vol - lower_vol)

    target_moneyness = spot_price / target_strike
    vol_adjustment = smile_adjustment(target_moneyness, smile_data[:atm_vol])

    interpolated_vol * vol_adjustment
  end

  def smile_adjustment(moneyness, atm_vol)
    # More aggressive skew parameters based on SPX characteristics

    if moneyness < 0.85  # Deep OTM puts (15%+ OTM)
      # Very steep skew - crash protection premium
      skew_factor = 1.0 + 3.0 * (0.85 - moneyness) + 5.0 * (0.85 - moneyness)**2

    elsif moneyness < 0.95  # OTM puts (5-15% OTM)
      # Moderate put skew
      skew_factor = 1.0 + 1.5 * (0.95 - moneyness) + 2.0 * (0.95 - moneyness)**2

    elsif moneyness <= 1.05  # ATM region (±5%)
      # Minimal adjustment near ATM
      skew_factor = 1.0 + 0.1 * (1.0 - moneyness)**2

    elsif moneyness < 1.15  # OTM calls (5-15% OTM)
      # Slight call wing uptick
      skew_factor = 1.0 + 0.3 * (moneyness - 1.05) + 0.5 * (moneyness - 1.05)**2

    else  # Deep OTM calls (15%+ OTM)
      # Moderate call wing volatility increase
      skew_factor = 1.0 + 0.5 * (moneyness - 1.15) + 1.0 * (moneyness - 1.15)**2
    end

    # Bound the adjustment (allow up to 8x volatility for extreme strikes)
    [[skew_factor, 0.3].max, 8.0].min
  end

  def calculate_atm_volatility(surface, spot_price)
    return nil if surface.empty?

    nearest_expiry = surface.keys.min_by { |exp| surface[exp][:time_to_expiry] }
    return nil unless nearest_expiry

    surface[nearest_expiry][:atm_vol]
  end

  def calculate_time_to_expiry(timestamp_ns, expiration_date)
    timestamp_sec = timestamp_ns / 1_000_000_000.0
    current_time = Time.at(timestamp_sec)
    expiry_time = Time.new(expiration_date.year, expiration_date.month, expiration_date.day, 16, 0, 0, '-05:00')
    days_to_expiry = (expiry_time - current_time) / (24 * 60 * 60)
    days_to_expiry / 365.25
  end

  def calculate_implied_volatility(market_price:, spot_price:, strike:, time_to_expiry:, risk_free_rate:, option_type:)
    objective_function = lambda do |vol|
      price = black_scholes_price(spot_price, strike, time_to_expiry, risk_free_rate, vol, option_type)
      price - market_price
    end

    vol_low, vol_high = 0.001, 5.0
    f_low = objective_function.call(vol_low)
    f_high = objective_function.call(vol_high)

    return nil if f_low * f_high > 0

    brent_method(objective_function, vol_low, vol_high, 1e-6)
  end

  def black_scholes_price(spot, strike, time_to_expiry, risk_free_rate, volatility, option_type)
    d1 = (Math.log(spot / strike) + (risk_free_rate + 0.5 * volatility**2) * time_to_expiry) /
         (volatility * Math.sqrt(time_to_expiry))
    d2 = d1 - volatility * Math.sqrt(time_to_expiry)

    case option_type.upcase
    when 'CALL'
      spot * norm_cdf(d1) - strike * Math.exp(-risk_free_rate * time_to_expiry) * norm_cdf(d2)
    when 'PUT'
      strike * Math.exp(-risk_free_rate * time_to_expiry) * norm_cdf(-d2) - spot * norm_cdf(-d1)
    end
  end

  def calculate_delta_from_price_history(current_price, previous_price, current_spot, previous_spot)
    spot_change = current_spot - previous_spot
    price_change = current_price - previous_price

    return nil if spot_change.abs < 0.01  # Avoid division by tiny numbers

    delta = price_change / spot_change

    # Sanity check the result
    return nil if delta.abs > 1.0  # Delta can't exceed 1.0 for single options

    delta
  end

  def calculate_market_delta(option_price, spot_price, strike, time_to_expiry, option_type, current_iv = nil, risk_free_rate = 0.045)
    bump = spot_price * 0.09  # 0.5% bump

    return nil unless current_iv

    price_up = black_scholes_price(
      spot_price + bump, strike, time_to_expiry, risk_free_rate, current_iv, option_type
    )

    price_down = black_scholes_price(
      spot_price - bump, strike, time_to_expiry, risk_free_rate, current_iv, option_type
    )

    delta = (price_up - price_down) / (2 * bump)

    delta
  end

  def calculate_black_scholes_delta(spot_price:, strike:, time_to_expiry:, risk_free_rate:, volatility:, option_type:)
    d1 = (Math.log(spot_price / strike) + (risk_free_rate + 0.5 * volatility**2) * time_to_expiry) /
         (volatility * Math.sqrt(time_to_expiry))

    case option_type.upcase
    when 'CALL'
      norm_cdf(d1)
    when 'PUT'
      norm_cdf(d1) - 1
    end
  end

  def norm_cdf(x)
    return 0.0 if x < -10
    return 1.0 if x > 10

    sign = x >= 0 ? 1 : -1
    x = x.abs

    a1, a2, a3, a4, a5, p = 0.254829592, -0.284496736, 1.421413741, -1.453152027, 1.061405429, 0.3275911
    t = 1.0 / (1.0 + p * x)
    y = 1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * Math.exp(-x * x)

    0.5 * (1.0 + sign * y)
  end

  def brent_method(func, a, b, tolerance, max_iterations = 100)
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

def build_options_chain_from_records(records, underlying_symbol)
  call_opts = []
  put_opts = []
  records.each do |record|
    if record.contract_type == "CALL"
      call_opts << OptionsTrader::DataObjects::Option.new(
        symbol: record.symbol,
        underlying_symbol: underlying_symbol,
        strike: record.strike,
        put_call: record.contract_type,
        mark: record.mark,
        underlying_price: record.underlying_price,
        expiration_date: record.expiration_date,
        days_to_expiration: (Date.parse(record.expiration_date.to_s) - Date.parse(record.valid_time.to_s)).to_i,
        delta: record.delta,
        gamma: record.gamma,
        theta: record.theta,
        vega: record.vega,
        rho: record.rho,
        open_interest: record.open_interest,
        total_volume: record.volume,
        option_root: 'SPXW',
        in_the_money: record.strike < record.underlying_price
      )
    else
      put_opts << OptionsTrader::DataObjects::Option.new(
        symbol: record.symbol,
        underlying_symbol: underlying_symbol,
        strike: record.strike,
        put_call: record.contract_type,
        mark: record.mark,
        underlying_price: record.underlying_price,
        expiration_date: record.expiration_date,
        days_to_expiration: (Date.parse(record.expiration_date.to_s) - Date.parse(record.valid_time.to_s)).to_i,
        delta: record.delta,
        gamma: record.gamma,
        theta: record.theta,
        vega: record.vega,
        rho: record.rho,
        open_interest: record.open_interest,
        total_volume: record.volume,
        option_root: 'SPXW',
        in_the_money: record.strike > record.underlying_price
      )
    end
  end

  OptionsTrader::DataObjects::OptionsChain.new(
    symbol: 'SPX',
    call_opts: call_opts,
    put_opts: put_opts
  )
end

underlying_symbol = '$SPX'

records = OptionsTrader::OptionChainHistory
  .where(expiration_date: '2025-08-18')
  .where(valid_time: '2025-08-11 14:24:18')

opts_chain = build_options_chain_from_records(records, underlying_symbol)
surface_builder = VolatilitySurfaceBuilder.new

timestamp = Time.parse('2025-08-11 14:24:18').to_i * 1_000_000_000
spot_price = records.first.underlying_price

puts "Building volatility surface for #{opts_chain.call_opts.length} calls and #{opts_chain.put_opts.length} puts"
puts "Spot price: #{spot_price}"

surface = surface_builder.build_surface_from_chain(timestamp, spot_price, opts_chain)

if surface
  puts "\nVolatility Surface Built Successfully!"
  surface.each do |expiry, data|
    puts "Expiry: #{expiry}, Time to expiry: #{data[:time_to_expiry].round(4)} years, ATM Vol: #{(data[:atm_vol] * 100).round(2)}%"
    vol_strikes = data[:smile][:vol_points]&.keys || []
    puts "  Volatility points: #{vol_strikes.length}"
  end

  puts "\nMarket regime: #{surface_builder.detect_volatility_regime}"
  puts "\nTesting volatility lookup for some strikes:"

  test_expiry = Date.parse('2025-08-18')

  puts "\nDelta Validation Test - Comparing stored deltas vs surface-calculated deltas:"
  puts "=" * 80

  delta_differences = []
  test_count = 0

  records.each do |record|
    surface_delta = surface_builder.calculate_delta_from_surface(
      record.strike,
      Date.parse(record.expiration_date.to_s),
      record.contract_type,
      timestamp,
      spot_price
    )

    if surface_delta && record.delta && record.delta.abs < 0.4 && record.delta.abs > 0.01
      stored_delta = record.delta
      difference = (surface_delta - stored_delta).abs
      delta_differences << difference
      test_count += 1

      puts "#{record.contract_type} Strike #{record.strike.to_i}: " +
           "Stored=#{stored_delta.round(4)}, Surface=#{surface_delta.round(4)}, " +
           "Diff=#{difference.round(6)}"
    end
  end

  if delta_differences.any?
    avg_diff = delta_differences.sum / delta_differences.length
    max_diff = delta_differences.max
    puts "\nDelta Validation Summary:"
    puts "  Tests run: #{test_count}"
    puts "  Average difference: #{avg_diff.round(6)}"
    puts "  Maximum difference: #{max_diff.round(6)}"
    puts "  Validation: #{max_diff < 0.01 ? 'PASS' : 'REVIEW'} (threshold: 0.01)"
  end

  puts "\nGenerating delta comparison charts..."

  # Collect actual vs calculated deltas for charting
  call_actual_deltas = []
  call_calculated_deltas = []
  put_actual_deltas = []
  put_calculated_deltas = []

  records.each do |record|
    surface_delta = surface_builder.calculate_delta_from_surface(
      record.strike,
      Date.parse(record.expiration_date.to_s),
      record.contract_type,
      timestamp,
      spot_price
    )

    if surface_delta && record.delta
      if record.contract_type == 'CALL'
        call_actual_deltas << [record.strike, record.delta]
        call_calculated_deltas << [record.strike, surface_delta]
      else
        put_actual_deltas << [record.strike, record.delta]
        put_calculated_deltas << [record.strike, surface_delta]
      end
    end
  end

  # Generate comparison charts for both calls and puts
  delta_chart = OptionsTrader::Charts::CompareDeltas.new

  if !call_actual_deltas.empty? && !call_calculated_deltas.empty?
    call_chart_path = delta_chart.generate(
      call_actual_deltas,
      call_calculated_deltas,
      'CALL',
      test_expiry
    )
    puts "Call delta comparison chart saved to: #{call_chart_path}"
  end

  if !put_actual_deltas.empty? && !put_calculated_deltas.empty?
    put_chart_path = delta_chart.generate(
      put_actual_deltas,
      put_calculated_deltas,
      'PUT',
      test_expiry
    )
    puts "Put delta comparison chart saved to: #{put_chart_path}"
  end
else
  puts "Failed to build volatility surface - insufficient liquid options"
end

binding.pry