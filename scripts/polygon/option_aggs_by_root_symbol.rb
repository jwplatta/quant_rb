#!/usr/bin/env ruby

require 'csv'
require 'fileutils'
require 'date'
require 'optparse'

# Script to organize option aggregates by root symbol
# Takes files like /Volumes/ext_docs/options_trader/polygon/minute_aggs_v1/2023/09/2023-09-26.csv
# And creates separate files for each root symbol like:
# /Volumes/ext_docs/options_trader/polygon/minute_aggs_v1/2023/09/26/ZZZ.csv
#
# Usage:
#   ruby option_aggs_by_root_symbol.rb                 # Process all symbols
#   ruby option_aggs_by_root_symbol.rb --symbol SPXW   # Process only SPXW symbol

BASE_DIR = "/Volumes/ext_docs/options_trader/polygon/minute_aggs_v1"

def extract_root_symbol(ticker)
  # Extract root symbol from options ticker (e.g., "O:ZZZ240119C00005000" -> "ZZZ")
  return nil unless ticker&.start_with?('O:')

  match = ticker.match(/^O:([A-Z]+)/)
  match ? match[1] : nil
end

def process_file(file_path, target_symbol = nil)
  puts "Processing #{file_path}#{target_symbol ? " (filtering for #{target_symbol})" : ""}..."

  # Parse the date from filename (e.g., "2023-09-26.csv" -> Date(2023, 9, 26))
  filename = File.basename(file_path, '.csv')
  date = Date.parse(filename)
  day = date.day

  # Create output directory structure
  year_month_dir = File.dirname(file_path)
  day_dir = File.join(year_month_dir, day.to_s)
  FileUtils.mkdir_p(day_dir)

  symbol_groups = {}
  headers = nil

  begin
    CSV.foreach(file_path, headers: true) do |row|
      # Store headers from first row
      headers ||= row.headers

      ticker = row['ticker']
      root_symbol = extract_root_symbol(ticker)

      if root_symbol
        # If target_symbol is specified, only process that symbol
        if target_symbol.nil? || root_symbol == target_symbol
          symbol_groups[root_symbol] ||= []
          symbol_groups[root_symbol] << row
        end
      else
        puts "Warning: Could not extract root symbol from ticker: #{ticker}" unless target_symbol
      end
    end

    # Write separate CSV files for each root symbol
    symbol_groups.each do |root_symbol, rows|
      output_file = File.join(day_dir, "#{root_symbol}.csv")

      # Delete existing file if it exists
      if File.exist?(output_file)
        File.delete(output_file)
        puts "  Deleted existing #{output_file}"
      end

      CSV.open(output_file, 'w', write_headers: true, headers: headers) do |csv|
        rows.each do |row|
          csv << row
        end
      end

      puts "  Created #{output_file} with #{rows.length} records"
    end

    if target_symbol
      if symbol_groups.key?(target_symbol)
        puts "  Found and processed #{target_symbol}"
      else
        puts "  No records found for #{target_symbol}"
      end
    else
      puts "  Processed #{symbol_groups.length} unique root symbols"
    end

  rescue StandardError => e
    puts "Error processing #{file_path}: #{e.message}"
  end
end

def find_and_process_files(target_symbol = nil)
  unless Dir.exist?(BASE_DIR)
    puts "Error: Base directory #{BASE_DIR} does not exist"
    exit 1
  end

  # Find all CSV files in the directory structure
  pattern = File.join(BASE_DIR, "**", "*.csv")
  csv_files = Dir.glob(pattern).select do |file|
    # Only process files that match the YYYY-MM-DD.csv pattern (not subdirectory files)
    File.basename(file) =~ /^\d{4}-\d{2}-\d{2}\.csv$/
  end

  if csv_files.empty?
    puts "No CSV files found matching pattern YYYY-MM-DD.csv in #{BASE_DIR}"
    exit 1
  end

  puts "Found #{csv_files.length} files to process"

  csv_files.sort.each do |file|
    process_file(file, target_symbol)
  end

  puts "\nProcessing complete!"
end

# Parse command line options
def parse_options
  options = {}
  
  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"
    
    opts.on('-s', '--symbol SYMBOL', 'Filter by specific root symbol (e.g., SPXW)') do |symbol|
      options[:symbol] = symbol.upcase
    end
    
    opts.on('-h', '--help', 'Show this help message') do
      puts opts
      exit
    end
  end.parse!
  
  options
end

# Main execution
if __FILE__ == $0
  options = parse_options
  target_symbol = options[:symbol]
  
  puts "Starting option aggregates organization by root symbol..."
  puts "Base directory: #{BASE_DIR}"
  puts "Target symbol: #{target_symbol || 'ALL'}"
  puts

  find_and_process_files(target_symbol)
end