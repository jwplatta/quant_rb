require 'json'
require 'pry'

def calculate_minute_returns(price_data)
  returns = []

  (1...price_data.length).each do |i|
    current_close = price_data[i]['close']
    previous_close = price_data[i-1]['close']

    returns << Math.log(current_close / previous_close)
  end

  returns
end

def standard_deviation(returns)
  mean = returns.sum / returns.length
  variance = returns.map { |r| (r - mean) ** 2 }.sum / (returns.length - 1)
  Math.sqrt(variance)
end

def calculate_short_term_realized_vol(price_data)
  # Use last N days of minute data
  returns = calculate_minute_returns(price_data)

  # Annualize for comparison
  std_dev = standard_deviation(returns)
  annualized_vol = std_dev * Math.sqrt(252 * 390)  # 390 minutes per trading day

  annualized_vol
end

file_path = '../tmp/response_1754698411677.json'
price_data = JSON.parse(File.read(file_path))

volatility = calculate_short_term_realized_vol(price_data['candles'])

puts "Short-term realized volatility: #{volatility.round(4)}"