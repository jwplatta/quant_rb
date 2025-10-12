# frozen_string_literal: true

total_earned = 0

1000.times do
  expected_reward = 100.0
  cost = 5.0

  result = rand # Generates a random float between 0.0 and 1.0

  total_earned -= cost

  if result > 0.13
    total_earned += expected_reward
  end
end

puts "Total earned after 1000 trades: $#{total_earned}"


# cost, reward, chance of success