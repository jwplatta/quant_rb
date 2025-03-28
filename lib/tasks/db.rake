require "fileutils"
require "yaml"
require "erb"
require "dotenv/load"

ENV["RACK_ENV"] ||= "development"

def db_config
  config_file = File.expand_path("../../../config/database.yml", __FILE__)
  YAML.load(ERB.new(File.read(config_file)).result, aliases: true)[ENV["RACK_ENV"]]
end

def db_path
  db_config["database"]
end

namespace :db do
  desc "Initialize the database"
  task :init do
    FileUtils.mkdir_p(File.dirname(db_path))

    unless File.exist?(db_path)
      FileUtils.touch(db_path)
      puts "Database file '#{db_path}' created successfully!"
    else
      puts "Database file '#{db_path}' already exists."
    end

    puts "✅ Database initialized!"
  end

  desc "Run migrations"
  task :migrate do
    require "active_record"
    system("bundle exec ruby db/migrations/create_tables.rb")
  end

  desc "Reset the database"
  task :reset => [:drop, :init, :migrate]

  desc "Drop the database"
  task :drop do
    if File.exist?(db_path)
      File.delete(db_path)
      puts "✅ Database '#{db_path}' dropped."
    else
      puts "Database file does not exist, nothing to drop."
    end
  end

  desc "Show current schema"
  task :schema do
    require "sqlite3"
    db = SQLite3::Database.new(db_path)
    result = db.execute("SELECT name, sql FROM sqlite_master WHERE type='table'")
    result.each do |table|
      puts "Table: #{table[0]}"
      puts table[1]
      puts
    end
    db.close
  end
end