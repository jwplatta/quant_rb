#!/usr/bin/env ruby

require 'csv'

# Initialize variables to store totals
commission_total = 0.0
fees_total = 0.0
premium_total = 0.0

# Path to the CSV file
csv_path = File.join(File.dirname(__FILE__), 'trades.csv')

File.foreach(csv_path) do |line|
  values = line.strip.split("\t")

  next if values.length < 3

  commission = values[0].to_f
  fees = values[1].to_f

  premium_str = values[2].to_s.strip
  premium = premium_str.empty? ? 0.0 : premium_str.gsub(',', '').to_f

  commission_total += commission
  fees_total += fees
  premium_total += premium
end

puts "Trade Summary"
puts "=============="
puts "Total Commission: $#{commission_total.round(2)}"
puts "Total Fees: $#{fees_total.round(2)}"
puts "Total Premium/Cost: $#{premium_total.round(2)}"
puts "=============="
puts "Overall Total: $#{(commission_total + fees_total + premium_total).round(2)}"
