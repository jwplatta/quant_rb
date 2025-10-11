require "pry"
require 'csv'
require_relative "../../lib/options_trader"

# This script generates a complete synthetic option chain by:
# 1. Fetching existing option prices using LOCF (Last Observation Carried Forward)
# 2. Generating complete strike range (underlying -3000 to +1000, all multiples of 5)
# 3. Interpolating prices for missing strikes using step-size algorithm

EXPIRATION_DATE = '2025-06-13'
VALID_TIME = '2025-06-10 14:20:00'
STALENESS_THRESHOLD_MINUTES = 120
UNDERLYING_SYMBOL = 'SPXW'
DEFAULT_MIN_MARK = 0.025
ROUND_TO = 3

Opt = Struct.new(
  :symbol,
  :strike,
  :contract_type,
  :mark,
  :underlying_price,
  :valid_time,
  :delta,
  :volume,
  :staleness,
  :synthetic
)

# Step 1: Reconstruct option chain using LOCF + Staleness Filter
def fetch_option_chain_locf(expiration_date, valid_time, staleness_thresh = 30)
  sql = <<-SQL
    WITH latest_prices AS (
      SELECT DISTINCT ON (symbol)
        symbol,
        strike,
        contract_type,
        mark,
        underlying_price,
        valid_time,
        volume,
        EXTRACT(EPOCH FROM (TIMESTAMP '#{valid_time}' - valid_time)) / 60 as staleness
      FROM option_chain_history
      WHERE expiration_date = '#{expiration_date}'
        AND valid_time <= '#{valid_time}'
        AND mark > 0
      ORDER BY symbol, valid_time DESC
    )
    SELECT * FROM latest_prices
    WHERE staleness < #{staleness_thresh}
    ORDER BY contract_type, strike;
  SQL

  records = OptionsTrader::OptionChainHistory.connection.execute(sql)

  calls = []
  put_opts = []
  underlying_price = nil

  records.each do |record|
    underlying_price ||= record['underlying_price'].to_f
    option_data = Opt.new(
      symbol: record['symbol'],
      strike: record['strike'].to_i,
      contract_type: record['contract_type'],
      mark: record['mark'].to_f,
      underlying_price: record['underlying_price'].to_f,
      valid_time: record['valid_time'],
      delta: record['delta']&.to_f,
      volume: record['volume']&.to_i || 0,
      staleness: record['staleness'].to_f.round(2),
      synthetic: false
    )

    if record['contract_type'] == 'CALL'
      calls << option_data
    else
      put_opts << option_data
    end
  end

  puts "  Calls: #{calls.length}"
  puts "  Puts: #{put_opts.length}"
  puts "  Underlying price: #{underlying_price}"

  [calls, put_opts, underlying_price]
end

# Step 2: Generate complete target strikes array
def generate_target_strikes(underlying_price, min_offset = -3000, max_offset = 1000, inner_offest = 225, inner_step = 5, outer_step = 25)
  # Round underlying to nearest 25
  base_strike = (underlying_price / outer_step.to_f).round * outer_step
  min_strike = base_strike + min_offset
  max_strike = base_strike + max_offset
  inner_min_strike = base_strike - inner_offest
  inner_max_strike = base_strike + inner_offest

  while inner_max_strike % outer_step != 0
    inner_max_strike += inner_step
  end

  strikes = []
  current_strike = min_strike

  while current_strike <= max_strike
    strikes << current_strike
    current_strike += current_strike >= inner_min_strike && current_strike < inner_max_strike ? inner_step : outer_step
  end

  strikes.sort
end

# Step 3: Build complete option arrays with synthetic options (nil marks)
def build_complete_option_arrays(calls, put_opts, target_strikes, underlying_price)
  min_strike = target_strikes.min
  max_strike = target_strikes.max
  calls_by_strike = calls.index_by { |o| o.strike.to_i }
  puts_by_strike = put_opts.index_by { |o| o.strike.to_i }

  complete_calls = []
  complete_puts = []

  target_strikes.each do |strike|
    if calls_by_strike[strike]
      complete_calls << calls_by_strike[strike]
    else
      complete_calls << if strike == max_strike
        create_option(strike, 'CALL', underlying_price, VALID_TIME, 1, DEFAULT_MIN_MARK, true)
      else
        create_option(strike, 'CALL', underlying_price, VALID_TIME, 1, nil, true)
      end
    end

    if puts_by_strike[strike]
      complete_puts << puts_by_strike[strike]
    else
      complete_puts << if strike == min_strike
        create_option(strike, 'PUT', underlying_price, VALID_TIME, 1, DEFAULT_MIN_MARK, true)
      else
        create_option(strike, 'PUT', underlying_price, VALID_TIME, 1, nil, true)
      end
    end
  end

  [complete_calls, complete_puts]
end

def create_option(strike, contract_type, underlying_price, valid_time, volume = 1, mark = nil, synthetic = false)
  Opt.new(
    symbol: create_option_symbol(strike, contract_type),
    strike: strike,
    mark: mark,
    delta: nil,
    volume: 1,
    underlying_price: underlying_price,
    contract_type: contract_type,
    valid_time: valid_time,
    synthetic: synthetic
  )
end

def create_option_symbol(strike, contract_type)
  "SPXW#{EXPIRATION_DATE.gsub('-', '')}#{contract_type[0]}#{(strike * 1000).to_i.to_s.rjust(8, '0')}"
end

# Step 3.5: Round marks to market convention (0.005 for SPX)
def round_marks!(options, increment = 0.05)
  options.each do |opt|
    opt.mark = (opt.mark / increment).round * increment
  end
end

# Main execution
puts "=== Building Synthetic Option Chain ==="
puts "Expiration: #{EXPIRATION_DATE}"
puts "Valid Time: #{VALID_TIME}"
puts ""

# Fetch existing options
puts "Fetching existing options..."
calls, put_opts, underlying_price = fetch_option_chain_locf(EXPIRATION_DATE, VALID_TIME, STALENESS_THRESHOLD_MINUTES)

puts "Found #{calls.length + put_opts.length} existing options"
puts "  #{calls.length} calls"
puts "  #{put_opts.length} puts"
puts ""
puts "Underlying price: #{underlying_price}"
puts ""

# Generate target strikes
puts "Generating target strikes..."
target_strikes = generate_target_strikes(underlying_price)
puts "Generated #{target_strikes.length} target strikes (#{target_strikes.first} to #{target_strikes.last})"
puts ""

# Build complete option arrays
puts "Building complete option arrays..."
complete_calls, complete_puts = build_complete_option_arrays(calls, put_opts, target_strikes, underlying_price)
puts "Complete calls: #{complete_calls.length}"
puts "Complete puts: #{complete_puts.length}"
puts ""

calls_needing_interpolation = complete_calls.count { |c| c.mark.nil? }
puts_needing_interpolation = complete_puts.count { |p| p.mark.nil? }
puts "Calls needing interpolation: #{calls_needing_interpolation}"
puts "Puts needing interpolation: #{puts_needing_interpolation}"

complete_calls = OptionsTrader::Utils::OptionPriceInterpolator.interpolate(complete_calls, contract_type: 'CALL')
complete_puts = OptionsTrader::Utils::OptionPriceInterpolator.interpolate(complete_puts, contract_type: 'PUT')

puts ""
puts "=== Enforcing Monotonicity ==="
complete_calls = OptionsTrader::Utils::MonotonicityEnforcer.enforce(complete_calls, contract_type: 'CALL')
complete_puts = OptionsTrader::Utils::MonotonicityEnforcer.enforce(complete_puts, contract_type: 'PUT')

calls_still_nil = complete_calls.count { |c| c.mark.nil? }
puts_still_nil = complete_puts.count { |p| p.mark.nil? }

if calls_still_nil > 0 || puts_still_nil > 0
  puts "WARNING: Still have nil marks - calls: #{calls_still_nil}, puts: #{puts_still_nil}"
else
  puts "SUCCESS: All options have interpolated prices"
end

puts ""
puts "=== Writing to CSV ==="

valid_time_str = VALID_TIME.is_a?(String) ? VALID_TIME.gsub(/[:\s-]/, '_') : VALID_TIME.strftime('%Y%m%d_%H%M')
csv_filename = "tmp/synthetic_option_chain_#{EXPIRATION_DATE}_#{valid_time_str}.csv"
puts "Writing to #{csv_filename}..."

CSV.open(csv_filename, 'w') do |csv|
  csv << ['call_mark', 'call_synthetic', 'strike', 'put_mark', 'put_synthetic']

  # Create hash for fast lookup
  calls_by_strike = complete_calls.index_by(&:strike)
  puts_by_strike = complete_puts.index_by(&:strike)

  all_strikes = (complete_calls.map(&:strike) + complete_puts.map(&:strike)).uniq.sort

  all_strikes.each do |strike|
    call_mark = calls_by_strike[strike]&.mark&.round(ROUND_TO) || ''
    call_synthetic = calls_by_strike[strike]&.synthetic ? 'S' : ''
    put_mark = puts_by_strike[strike]&.mark&.round(ROUND_TO) || ''
    put_synthetic = puts_by_strike[strike]&.synthetic ? 'S' : ''
    csv << [call_mark, call_synthetic, strike, put_mark, put_synthetic]
  end
end

puts "CSV written successfully!"
puts ""

puts "=== Generating Call Price Chart (Non-Synthetic) ==="
non_synthetic_calls = complete_calls #.reject { |c| c.synthetic }
chart_data = non_synthetic_calls.map { |c| [c.strike, c.mark] }
puts "Plotting #{chart_data.length} non-synthetic calls"
line_graph = OptionsTrader::Charts::LineGraph.new(width: 1200, height: 800)
chart_path = line_graph.generate(
  chart_data,
  title: "Call Prices (Non-Synthetic) - #{EXPIRATION_DATE} @ #{VALID_TIME}",
  x_axis_label: "Strike",
  y_axis_label: "Price",
  vertical_line: underlying_price,
  vertical_line_label: "Spot: #{underlying_price}",
  output_filename: "call_prices_non_synthetic_#{EXPIRATION_DATE}_#{valid_time_str}.png"
)
puts "Chart saved to: #{chart_path}"
puts ""

puts "=== Synthetic Option Chain Complete ==="
