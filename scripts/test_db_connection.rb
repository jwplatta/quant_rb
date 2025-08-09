#!/usr/bin/env ruby

require_relative '../lib/options_trader'
require 'pry'

puts "🔍 Testing Database Connection"
puts "=" * 60

current_env = ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'development'

puts "\n📋 Current Environment: #{current_env}"

# Test database connection
puts "\n🔌 Testing Database Connection:"
begin
  # Test the actual connection by getting database info
  current_db = ActiveRecord::Base.connection.current_database
  puts "  ✅ Successfully connected to database"
  puts "  ✅ Connected to: #{current_db}"

  # Get connection configuration
  db_config = ActiveRecord::Base.connection_db_config.configuration_hash
  puts "\n⚙️  Database Configuration:"
  puts "  Host: #{db_config[:host] || 'localhost'}"
  puts "  Port: #{db_config[:port] || 5432}"
  puts "  Database: #{db_config[:database]}"
  puts "  Username: #{db_config[:username]}"
  puts "  Password set: #{!db_config[:password].nil? && !db_config[:password].empty?}"

  # Test a simple query
  result = ActiveRecord::Base.connection.execute("SELECT version();")
  version = result.first['version'] if result.any?
  puts "  ✅ Database connection is active"
  puts "  ✅ PostgreSQL Version: #{version.split(' ')[0..1].join(' ')}" if version

  # Test table existence (if migrations have been run)
  if ActiveRecord::Base.connection.table_exists?('option_chain_history')
    puts "  ✅ option_chain_history table exists"

    # Count records if table exists
    count = OptionsTrader::OptionChainHistory.count
    puts "  📊 option_chain_history records: #{count}"

    # Show table schema info
    columns = ActiveRecord::Base.connection.columns('option_chain_history')
    puts "  📋 Table columns: #{columns.size} total"
    puts "     Key columns: symbol, underlying_symbol, strike, contract_type, expiration_date"
    puts "     Price columns: bid, ask, mark, last_price, underlying_price"
    puts "     Greeks: delta, theta, vega, gamma, rho"
    puts "     Volume data: open_interest, volume, bid_size, ask_size"
  else
    puts "  ⚠️  option_chain_history table does not exist (run migrations)"
  end

rescue => e
  puts "  ❌ Failed to connect to database:"
  puts "     Error: #{e.class}: #{e.message}"

  # Additional debugging for common issues
  if e.message.include?('could not connect to server')
    puts "     💡 Check if database server is accessible"
    puts "     💡 Verify host and port are correct"
  elsif e.message.include?('authentication failed')
    puts "     💡 Check database username and password"
  elsif e.message.include?('database') && e.message.include?('does not exist')
    puts "     💡 Check database name - database may not exist"
  end
end

# Clean up connection
begin
  ActiveRecord::Base.connection_pool.disconnect!
  puts "\n🔌 Disconnected from database"
rescue => e
  puts "\n⚠️  Error disconnecting: #{e.message}"
end

puts "\n✨ Database connection test completed"