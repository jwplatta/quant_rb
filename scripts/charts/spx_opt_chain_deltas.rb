require "pry"
require_relative "../../lib/options_trader"
require_relative "../../lib/options_trader/charts/line_graph"

schwab_provider = OptionsTrader::DataProviders::Schwab::Markets.new
markets_service = OptionsTrader::Services::Markets.new(provider: schwab_provider)
symbol = '$SPX'

puts "Fetching option chain for #{symbol}..."

opt_chain = markets_service.get_option_chain(
  symbol,
  to_date: Date.parse('2025-10-09'),
  from_date: Date.parse('2025-10-09'),
  contract_type: 'ALL',
  strike_range: 'ALL'
)

puts "Fetched #{opt_chain.call_opts.length} call options"
puts "Fetched #{opt_chain.put_opts.length} put options"
puts "Underlying price: #{opt_chain.underlying_price}"

expiration_date = opt_chain.call_opts.first&.expiration_date || opt_chain.put_opts.first&.expiration_date

####################
### CALL DELTAS ###
####################

puts "\n=== Generating Call Delta Chart ==="

# Collect delta data from call options
call_delta_data = opt_chain.call_opts
  .select { |opt| opt.delta }  # Only include options with delta values
  .sort_by(&:strike)
  .map { |opt| [opt.strike, opt.delta] }

if call_delta_data.empty?
  puts "No call delta data available"
else
  puts "Generating call delta chart with #{call_delta_data.length} data points..."

  # Generate the call delta chart
  begin
    line_graph = OptionsTrader::Charts::LineGraph.new

    chart_data = {
      name: "Call Deltas",
      data: call_delta_data
    }

    chart_title = "SPX Call Deltas - Exp #{expiration_date}"

    chart_path = line_graph.generate(
      chart_data,
      title: chart_title,
      x_axis_label: "Strike Price ($)",
      y_axis_label: "Delta",
      min_y: 0.0,
      max_y: 1.0,
      vertical_line: opt_chain.underlying_price,
      vertical_line_label: "Spot Price",
      output_filename: "spx_call_deltas_#{expiration_date.to_s.gsub('-', '')}_#{Time.now.strftime('%Y%m%d_%H%M%S')}.png"
    )

    puts "Call delta chart saved to: #{chart_path}"
  rescue StandardError => e
    puts "Error generating call delta chart: #{e.message}"
    puts e.backtrace.first(5).join("\n")
  end
end

##################
### PUT DELTAS ###
##################

puts "\n=== Generating Put Delta Chart ==="

# Collect delta data from put options
put_delta_data = opt_chain.put_opts
  .select { |opt| opt.delta }  # Only include options with delta values
  .sort_by(&:strike)
  .map { |opt| [opt.strike, opt.delta] }

if put_delta_data.empty?
  puts "No put delta data available"
else
  puts "Generating put delta chart with #{put_delta_data.length} data points..."

  begin
    line_graph = OptionsTrader::Charts::LineGraph.new

    chart_data = {
      name: "Put Deltas",
      data: put_delta_data
    }

    chart_title = "SPX Put Deltas - Exp #{expiration_date}"

    chart_path = line_graph.generate(
      chart_data,
      title: chart_title,
      x_axis_label: "Strike Price ($)",
      y_axis_label: "Delta",
      min_y: -1.0,
      max_y: 0.0,
      vertical_line: opt_chain.underlying_price,
      vertical_line_label: "Spot Price",
      output_filename: "spx_put_deltas_#{expiration_date.to_s.gsub('-', '')}_#{Time.now.strftime('%Y%m%d_%H%M%S')}.png"
    )

    puts "Put delta chart saved to: #{chart_path}"
  rescue StandardError => e
    puts "Error generating put delta chart: #{e.message}"
    puts e.backtrace.first(5).join("\n")
  end
end

puts "\n=== Chart generation complete ==="
