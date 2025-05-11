# frozen_string_literal: true

# Example:
#  - Assume the price of a stock is $100 when I buy a CALL option (100 stocks) at $1.5 per contract with a strike price of $100.
#  - Also assume that the underlying stock has a %50 chance of rising to $104 at expiry.

total = 0
1000.times do |i|
  # orig_stock_price = 100
  stock_cnt = 100
  strike_price = 100
  # price_at_expiry = 104
  premium_per_contract = 1.4

  total += ((([100, 102, 103, 104,
               105].sample - strike_price) * 100 * [0, 1].sample) - (premium_per_contract * stock_cnt))
  puts "Total after iteration #{i + 1}: $#{total}"
end

puts "Total portfolio value after 1000 trades: $#{total}"
