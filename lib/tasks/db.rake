require 'active_record'
require 'pry'

namespace :db do
  desc "Initialize database connection"
  task :init do
    require_relative '../../config/environment'
    puts "Database connection initialized"
  end

  desc "Create database"
  task :create => :init do
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    db_name = config[:database]
    admin_config = config.merge(database: 'postgres')

    ActiveRecord::Base.establish_connection(admin_config)
    ActiveRecord::Base.connection.create_database(db_name)

    puts "Database '#{db_name}' created successfully"
  rescue ActiveRecord::DatabaseAlreadyExists
    puts "Database already exists"
  end

  desc "Run database migrations"
  task :migrate => :init do
    ActiveRecord::Base.connection_pool.disconnect!
    ActiveRecord::MigrationContext.new("db/migrate").migrate
    puts "Database migrated successfully"
  end

  desc "Rollback the last migration"
  task :rollback => :init do
    ActiveRecord::MigrationContext.new("db/migrate").rollback
    puts "Last migration rolled back"
  end

  desc "Rollback the last migration manually"
  task :rollback_manual => :init do
    # Get the last migration version
    result = ActiveRecord::Base.connection.execute(
      "SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1"
    )

    if result.any?
      last_version = result.first['version']
      puts "Rolling back migration version: #{last_version}"

      # Remove it from schema_migrations
      ActiveRecord::Base.connection.execute(
        "DELETE FROM schema_migrations WHERE version = '#{last_version}'"
      )

      puts "Migration #{last_version} manually rolled back from schema_migrations"
      puts "Note: You may need to manually drop/alter tables if needed"
    else
      puts "No migrations found to rollback"
    end
  end

  desc "Drop database"
  task :drop => :init do
    # Get the current database configuration from ActiveRecord
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    db_name = config[:database]
    admin_config = config.merge(database: 'postgres')

    ActiveRecord::Base.establish_connection(admin_config)
    ActiveRecord::Base.connection.drop_database(db_name)

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