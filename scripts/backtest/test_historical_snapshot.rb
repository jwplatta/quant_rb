require 'pry'
require_relative "../../lib/options_trader"

EXPIRATION_DATE = '2025-06-13'
VALID_TIME = '2025-06-10 14:20:00'
LOOKBACK_WINDOW = 5
UNDERLYING_SYMBOL = 'SPXW'

puts "=== Testing HistoricalSnapshot Service ==="
puts "Expiration: #{EXPIRATION_DATE}"
puts "Valid Time: #{VALID_TIME}"
puts ""

# Create a HistoricalSnapshot instance
snapshot_service = OptionsTrader::Services::HistoricalSnapshot.new(
  symbol: UNDERLYING_SYMBOL,
  valid_time: Time.parse(VALID_TIME),
  strike_range: []
)

puts "Fetching option chain..."
option_chain = snapshot_service.get_option_chain(
  UNDERLYING_SYMBOL,
  expiration_date: EXPIRATION_DATE,
  window: LOOKBACK_WINDOW
)

calls = option_chain.call_opts
puts_array = option_chain.put_opts
underlying_price = option_chain.underlying_price

puts "Results:"
puts "  Calls: #{calls.length}"
puts "  Puts: #{puts_array.length}"
puts "  Underlying price: #{underlying_price}"
puts ""

# Check for nil marks
calls_with_nil = calls.count { |c| c.mark.nil? }
puts_with_nil = puts_array.count { |p| p.mark.nil? }

if calls_with_nil > 0 || puts_with_nil > 0
  puts "ERROR: Found nil marks - calls: #{calls_with_nil}, puts: #{puts_with_nil}"
else
  puts "SUCCESS: All options have interpolated prices"
end
puts ""

# Check monotonicity
puts "Checking monotonicity..."
call_violations = 0
(0...calls.length - 1).each do |i|
  if calls[i].mark <= calls[i + 1].mark
    call_violations += 1
  end
end

put_violations = 0
(0...puts_array.length - 1).each do |i|
  if puts_array[i].mark >= puts_array[i + 1].mark
    put_violations += 1
  end
end

if call_violations > 0 || put_violations > 0
  puts "ERROR: Monotonicity violations - calls: #{call_violations}, puts: #{put_violations}"
else
  puts "SUCCESS: Monotonicity enforced correctly"
end
puts ""

# Show sample data
puts "Sample call options (first 5):"
calls.first(5).each do |opt|
  puts "  Strike: #{opt.strike}, Mark: #{opt.mark.round(3)}"
end
puts ""

puts "Sample put options (first 5):"
puts_array.first(5).each do |opt|
  puts "  Strike: #{opt.strike}, Mark: #{opt.mark.round(3)}"
end
puts ""

puts "=== Test Complete ==="

binding.pry