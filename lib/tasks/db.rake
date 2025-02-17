require "dotenv"
require "pry"
require "active_record"
require "yaml"

Dotenv.load

def establish_connection
  ActiveRecord::Base.establish_connection(
    adapter: "postgresql",
    database: ENV["DATABASE_NAME"],
    username: ENV["DATABASE_USER"],
    password: ENV["DATABASE_PASSWORD"],
    host: "localhost"
  )
end

namespace :db do
  desc "Initialize the database"
  task :init do
    establish_connection

    begin
      ActiveRecord::Base.connection
      puts "✅ Database already exists."
    rescue ActiveRecord::NoDatabaseError
      system("createdb your_database_name") # Only works for PostgreSQL
      puts "✅ Database created."
    end

    ActiveRecord::Base.connection.execute(<<-SQL)
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version VARCHAR(255) PRIMARY KEY
      );
    SQL

    puts "✅ Database initialized!"
  end

  desc "Run migrations"
  task :migrate do
    system("bundle exec ruby db/migrations/create_tables.rb")
  end

  # desc "Create a new migration"
  # task :create_migration, [:name] do |t, args|
  #   name = args[:name] || "new_migration"
  #   timestamp = Time.now.strftime("%Y%m%d%H%M%S")
  #   filename = "db/migrations/#{timestamp}_#{name}.rb"

  #   migration_template = <<-MIGRATION
  #     class #{name.split('_').map(&:capitalize).join} < ActiveRecord::Migration[6.1]
  #       def change
  #         # Define your migration here
  #       end
  #     end
  #   MIGRATION

  #   File.write(filename, migration_template)
  #   puts "✅ Created migration: #{filename}"
  # end
end
