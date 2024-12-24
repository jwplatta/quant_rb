total_earned = 0

1000.times do
  expected_reward = 2
  expected_risk = 1

  result = [0,1].sample

  if result == 1
    total_earned += expected_reward
  else
    total_earned -= expected_risk
  end
end

puts "Total earned after 1000 trades: $#{total_earned}"