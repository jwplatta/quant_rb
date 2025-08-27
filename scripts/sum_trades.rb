#!/usr/bin/env ruby

require 'csv'
require 'pry'

commission_total = 0.0
fees_total = 0.0
cost_total = 0.0

if ARGV.empty?
  puts "Usage: ruby sum_trades.rb <path_to_csv_file>"
  exit 1
end

csv_path = ARGV.first

CSV.foreach(csv_path, headers: true) do |row|
  hash = row.to_h

  fees = hash['fees'].to_f
  commission = hash['commission'].to_f
  cost = hash['cost'].to_f

  commission_total += commission
  fees_total += fees
  cost_total += cost
end

puts "Trade Summary"
puts "=============="
puts "Total Commission: $#{commission_total.round(2)}"
puts "Total Fees: $#{fees_total.round(2)}"
puts "Total Cost: $#{cost_total.round(2)}"
puts "=============="
puts "Overall Total: $#{(commission_total + fees_total + cost_total).round(2)}"
