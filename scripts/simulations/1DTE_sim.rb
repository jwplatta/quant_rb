# trading_sim.rb

SIM_CNT = 1000
TRADING_DAYS = 225
INITIAL_PORTFOLIO = 100_000.0
WIN_PROBABILITY = 0.9
CONTRACTS = 10
EXIT_PRICE = 0.4
EXIT_PRICES = [0.3, 0.4, 0.5, 0.8]
LOSS_MULTIPLIER = 3.0
CONTRACT_PRICE = 1.25
FEES = 2.6
COMMISSION = 2.6

sim_prof_results = []

SIM_CNT.times do |sim|
  portfolio = INITIAL_PORTFOLIO
  daily_log = []

  TRADING_DAYS.times do |day|
    profit = 0

    premium = CONTRACTS * CONTRACT_PRICE * 100 - FEES * CONTRACTS - COMMISSION * CONTRACTS

    profit_loss = if rand < WIN_PROBABILITY
      premium - (CONTRACTS * EXIT_PRICES.sample * 100) - FEES * CONTRACTS - COMMISSION * CONTRACTS
    else
      premium - CONTRACTS * CONTRACT_PRICE * LOSS_MULTIPLIER * 100 - FEES * CONTRACTS - COMMISSION * CONTRACTS
    end

    portfolio += profit_loss

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