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

def admin_connection
  ActiveRecord::Base.establish_connection(
    adapter:  'postgresql',
    host:     'localhost',
    database: 'postgres',
  )
end

namespace :db do
  desc "Initialize the database"
  task :init do
    admin_connection

    db_user = ENV["DATABASE_USER"]
    db_password = ENV["DATABASE_PASSWORD"]
    db_name = ENV["DATABASE_NAME"]

    ActiveRecord::Base.connection.execute(
      "DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '#{db_user}') THEN CREATE USER #{db_user} WITH PASSWORD '#{db_password}'; END IF; END $$;"
    )
    ActiveRecord::Base.connection.execute("ALTER USER #{db_user} WITH SUPERUSER;")

    existing_db = ActiveRecord::Base.connection.exec_query("SELECT 1 FROM pg_database WHERE datname = '#{db_name}'").to_a

    if existing_db.empty?
      ActiveRecord::Base.connection.create_database(db_name)
      puts "Database '#{db_name}' created successfully!"
    else
      puts "Database '#{db_name}' already exists."
    end

    ActiveRecord::Base.connection.execute("ALTER DATABASE #{db_name} OWNER TO #{db_user};")
    ActiveRecord::Base.connection.execute("GRANT ALL PRIVILEGES ON DATABASE #{db_name} TO #{db_user};")

    puts "User '#{db_user}' now has full control over '#{db_name}'."
    puts "✅ Database initialized!"
  end

  desc "Run migrations"
  task :migrate do
    system("bundle exec ruby db/migrations/create_tables.rb")
  end

  desc "Reset the database"
  task :reset => [:drop, :init, :migrate]

  desc "Drop the database"
  task :drop do
    admin_connection
    ActiveRecord::Base.connection.drop_database(ENV["DATABASE_NAME"])
    db_user = ENV["DATABASE_USER"]
    ActiveRecord::Base.connection.execute("DROP USER IF EXISTS #{db_user};")
    puts "✅ Database dropped."
  end
end
