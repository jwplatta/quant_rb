require 'active_record'

namespace :db do
  desc "Initialize database connection"
  task :init do
    require_relative '../options_trader'
    OptionsTrader::DB.connect!
    puts "Database connection initialized"
  end

  desc "Create database"
  task :create => :init do
    config = OptionsTrader::DB.send(:build_config)
    
    if config[:url]
      # Parse URL to get database name and connection without database
      uri = URI.parse(config[:url])
      db_name = uri.path[1..-1] # Remove leading slash
      base_url = config[:url].gsub(/\/#{db_name}(\?.*)?$/, '/postgres')
      
      ActiveRecord::Base.establish_connection(url: base_url)
      ActiveRecord::Base.connection.create_database(db_name)
    else
      db_name = config[:database]
      admin_config = config.merge(database: 'postgres')
      
      ActiveRecord::Base.establish_connection(admin_config)
      ActiveRecord::Base.connection.create_database(db_name)
    end
    
    puts "Database '#{db_name || 'from URL'}' created successfully"
  rescue ActiveRecord::DatabaseAlreadyExists
    puts "Database already exists"
  end

  desc "Run database migrations"
  task :migrate => :init do
    ActiveRecord::MigrationContext.new("db/migrate").migrate
    puts "Database migrated successfully"
  end

  desc "Rollback the last migration"
  task :rollback => :init do
    ActiveRecord::MigrationContext.new("db/migrate").rollback
    puts "Last migration rolled back"
  end

  desc "Drop database"
  task :drop => :init do
    config = OptionsTrader::DB.send(:build_config)
    
    if config[:url]
      uri = URI.parse(config[:url])
      db_name = uri.path[1..-1]
      base_url = config[:url].gsub(/\/#{db_name}(\?.*)?$/, '/postgres')
      
      ActiveRecord::Base.establish_connection(url: base_url)
      ActiveRecord::Base.connection.drop_database(db_name)
    else
      db_name = config[:database]
      admin_config = config.merge(database: 'postgres')
      
      ActiveRecord::Base.establish_connection(admin_config)
      ActiveRecord::Base.connection.drop_database(db_name)
    end
    
    puts "Database dropped successfully"
  end

  desc "Reset database (drop, create, migrate)"
  task :reset => [:drop, :create, :migrate] do
    puts "Database reset completed"
  end

  desc "Load schema information"
  task :schema => :init do
    puts "Current database schema:"
    ActiveRecord::Base.connection.tables.each do |table|
      puts "- #{table}"
    end
  end

  desc "Load seed data"
  task :seed => :init do
    seed_file = "db/seeds.rb"
    if File.exist?(seed_file)
      load seed_file
      puts "Seed data loaded"
    else
      puts "No seed file found at #{seed_file}"
    end
  end
end