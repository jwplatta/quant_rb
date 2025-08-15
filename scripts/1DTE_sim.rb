# trading_sim.rb

SIM_CNT = 1000
TRADING_DAYS = 100
INITIAL_PORTFOLIO = 200_000.0
TRADING_PERCENTAGE = 0.3
WIN_PROBABILITY = 0.9
RETURN_RATE = 0.04
LOSS_MULTIPLIER = 4.0

sim_prof_results = []

SIM_CNT.times do |sim|
  portfolio = INITIAL_PORTFOLIO
  daily_log = []

  TRADING_DAYS.times do |day|
    tradable_capital = portfolio * TRADING_PERCENTAGE
    profit = 0

    if rand < WIN_PROBABILITY
      # Win: earn 5% on tradable capital
      profit = tradable_capital * RETURN_RATE
    else
      # Loss: lose 4x the potential profit
      potential_profit = tradable_capital * RETURN_RATE
      profit = -potential_profit * LOSS_MULTIPLIER
    end

    portfolio += profit

    daily_log << {
      day: day + 1,
      result: profit >= 0 ? "WIN" : "LOSS",
      profit: profit.round(2),
      portfolio: portfolio.round(2)
    }
  end

  puts "Final Portfolio Value: $#{portfolio.round(2)}"
  net_prof = (portfolio.round(2) - INITIAL_PORTFOLIO).round(2)
  puts "Net Profit: $#{net_prof}"
  sim_prof_results << net_prof
  # puts "\n--- Daily Log ---"
  # daily_log.each do |entry|
  #   puts "Day #{entry[:day]}: #{entry[:result]} | Profit: $#{entry[:profit]} | Portfolio: $#{entry[:portfolio]}"
  # end
end

puts "\n--- Simulation Summary ---"
avg_profit = sim_prof_results.sum / sim_prof_results.size.to_f
puts "Average Net Profit over #{SIM_CNT} simulations: $#{avg_profit.round(2)}"