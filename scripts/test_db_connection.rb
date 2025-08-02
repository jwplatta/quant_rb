#!/usr/bin/env ruby

require_relative '../lib/options_trader'
require_relative '../lib/options_trader/db'

puts "🔍 Testing Database Connection to Supabase PostgreSQL"
puts "=" * 60

# Test environment variables loading
puts "\n📋 Environment Variables:"
puts "  DATABASE_HOST: #{ENV['DATABASE_HOST']}"
puts "  DATABASE_PORT: #{ENV['DATABASE_PORT']}"
puts "  DATABASE_NAME: #{ENV['DATABASE_NAME']}"
puts "  DATABASE_USER: #{ENV['DATABASE_USER']}"
puts "  DATABASE_PASSWORD: #{ENV['DATABASE_PASSWORD'] ? '[HIDDEN]' : '[NOT SET]'}"

# Test configuration loading
puts "\n⚙️  Configuration Values:"
puts "  Host: #{OptionsTrader.db_host}"
puts "  Port: #{OptionsTrader.db_port}"
puts "  Database: #{OptionsTrader.db_name}"
puts "  User: #{OptionsTrader.db_user}"
puts "  Password set: #{!OptionsTrader.db_password.nil? && !OptionsTrader.db_password.empty?}"
puts "  Database configured: #{OptionsTrader.database_configured?}"

# Test database connection
puts "\n🔌 Testing Database Connection:"
begin
  if OptionsTrader.database_configured?
    puts "  ✅ Database configuration is valid"

    # Attempt to connect
    OptionsTrader::DB.connect!
    puts "  ✅ Successfully connected to database"
    # Test if we're actually connected by running actual queries
    begin
      # Test a simple query
      result = ActiveRecord::Base.connection.execute("SELECT version();")
      version = result.first['version'] if result.any?
      puts "  ✅ Database connection is active"
      puts "  ✅ PostgreSQL Version: #{version.split(' ')[0..1].join(' ')}" if version
      
      # Test table existence (if migrations have been run)
      if ActiveRecord::Base.connection.table_exists?('option_chain_history')
        puts "  ✅ option_chain_history table exists"

        # Count records if table exists
        require_relative '../lib/options_trader/models/option_chain_history'
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
      puts "  ❌ Database connection test failed: #{e.message}"
      puts "     This suggests the connection is not working properly"
    end

  else
    puts "  ❌ Database is not properly configured"
    puts "     Missing required environment variables"
  end

rescue => e
  puts "  ❌ Failed to connect to database:"
  puts "     Error: #{e.class}: #{e.message}"

  # Additional debugging for common issues
  if e.message.include?('could not connect to server')
    puts "     💡 Check if Supabase database is accessible"
    puts "     💡 Verify host and port are correct"
  elsif e.message.include?('authentication failed')
    puts "     💡 Check DATABASE_USER and DATABASE_PASSWORD"
  elsif e.message.include?('database') && e.message.include?('does not exist')
    puts "     💡 Check DATABASE_NAME - database may not exist"
  end
end

# Clean up connection
begin
  OptionsTrader::DB.disconnect!
  puts "\n🔌 Disconnected from database"
rescue => e
  puts "\n⚠️  Error disconnecting: #{e.message}"
end

puts "\n✨ Database connection test completed"