require 'active_record'
require 'pry'

namespace :db do
  desc "Initialize database connection"
  task :init do
    require_relative '../../config/environment'
    puts "Connected to #{ActiveRecord::Base.connection_db_config.configuration_hash}"
  end

  desc "Create database"
  task :create => :init do
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    db_name = config[:database]
    username = config[:username]
    admin_config = config.merge(database: 'postgres', username: ENV['USER'])

    begin
      ActiveRecord::Base.connection_pool.disconnect!
      ActiveRecord::Base.establish_connection(admin_config)
      ActiveRecord::Base.connection.create_database(db_name)
      created = true
      puts "Database '#{db_name}' created successfully"
    rescue ActiveRecord::DatabaseAlreadyExists
      puts "Database '#{db_name}' already exists"
      created = false
    end

    ActiveRecord::Base.establish_connection(admin_config)

    begin
      ActiveRecord::Base.connection.execute("CREATE USER #{username}")
    rescue ActiveRecord::StatementInvalid => e
      # User already exists, that's fine
    end
    ActiveRecord::Base.connection.execute("ALTER USER #{username} CREATEDB")

    ActiveRecord::Base.connection.execute("GRANT ALL PRIVILEGES ON DATABASE #{db_name} TO #{username}")

    db_config = config.merge(database: db_name, username: ENV['USER'])
    ActiveRecord::Base.establish_connection(db_config)
    ActiveRecord::Base.connection.execute("GRANT ALL PRIVILEGES ON SCHEMA public TO #{username}")
    ActiveRecord::Base.connection.execute("GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO #{username}")
    ActiveRecord::Base.connection.execute("GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO #{username}")
    ActiveRecord::Base.connection.execute("GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO #{username}")
    ActiveRecord::Base.connection.execute("ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO #{username}")
    ActiveRecord::Base.connection.execute("ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO #{username}")
    ActiveRecord::Base.connection.execute("ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO #{username}")

    puts "Comprehensive permissions granted to #{username}"
  end

  desc "Run database migrations"
  task :migrate => :init do
    ActiveRecord::Base.connection_pool.disconnect!

    config = ActiveRecord::Base.connection_db_config.configuration_hash
    ActiveRecord::Base.establish_connection(config)
    ActiveRecord::MigrationContext.new("db/migrate").migrate
    puts "Database migrated successfully"
  end

  desc "Rollback the last migration"
  task :rollback => :init do
    ActiveRecord::Base.connection_pool.disconnect!
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    ActiveRecord::Base.establish_connection(config)
    ActiveRecord::MigrationContext.new("db/migrate").rollback
    puts "Last migration rolled back"
  end

  desc "Rollback the last migration manually"
  task :rollback_manual => :init do
    ActiveRecord::Base.connection_pool.disconnect!
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    ActiveRecord::Base.establish_connection(config)
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
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    db_name = config[:database]
    admin_config = config.merge(database: 'postgres', username: ENV['USER'])

    ActiveRecord::Base.connection_pool.disconnect!
    ActiveRecord::Base.establish_connection(admin_config)
    ActiveRecord::Base.connection.drop_database(db_name)
    ActiveRecord::Base.connection_pool.disconnect!

    puts "Database dropped successfully"
  end

  desc "Load schema information"
  task :schema => :init do
    puts "Current database schema:"
    ActiveRecord::Base.connection.tables.each do |table|
      puts "- #{table}"
    end
  end

  desc "Reindex individual indexes one at a time"
  task :reindex, [:table_name] => :init do |t, args|
    table_name = args[:table_name]

    unless table_name
      puts "Error: Please provide a table name"
      puts "Usage: rake db:reindex_individual[table_name]"
      exit 1
    end

    index_query = <<-SQL
      SELECT
        indexname,
        pg_size_pretty(pg_relation_size(indexname::regclass)) as size
      FROM pg_indexes
      WHERE tablename = '#{table_name}'
      ORDER BY pg_relation_size(indexname::regclass) DESC
    SQL

    indexes = ActiveRecord::Base.connection.execute(index_query)

    puts "Indexes for #{table_name} (largest first):"
    indexes.each_with_index do |idx, i|
      puts "  #{i+1}. #{idx['indexname']} (#{idx['size']})"
    end

    puts "\nChoose indexes to reindex:"
    puts "  a) All indexes"
    puts "  s) Select specific indexes"
    puts "  1-#{indexes.count}) Individual index number"
    print "Choice: "

    choice = STDIN.gets.chomp.downcase

    selected_indexes = case choice
    when 'a'
      indexes
    when 's'
      puts "Enter index numbers (comma-separated, e.g., 1,3,5):"
      selected_nums = STDIN.gets.chomp.split(',').map(&:strip).map(&:to_i)
      selected_nums.map { |num| indexes[num-1] }.compact
    else
      num = choice.to_i
      if num > 0 && num <= indexes.count
        [indexes[num-1]]
      else
        puts "Invalid choice"
        exit 1
      end
    end

    puts "\nReindexing #{selected_indexes.count} indexes..."

    selected_indexes.each_with_index do |idx, i|
      index_name = idx['indexname']
      puts "\n[#{i+1}/#{selected_indexes.count}] Reindexing #{index_name} (#{idx['size']})..."

      start_time = Time.now
      begin
        ActiveRecord::Base.connection.execute("REINDEX INDEX #{index_name}")
        elapsed = Time.now - start_time
        puts "✓ Completed #{index_name} in #{elapsed.round(2)} seconds"
      rescue => e
        puts "✗ Error on #{index_name}: #{e.message}"
      end
    end

    puts "\n✓ Individual reindex completed"
  end

  desc "Show table size and index information"
  task :table_info, [:table_name] => :init do |t, args|
    table_name = args[:table_name]

    unless table_name
      puts "Error: Please provide a table name"
      puts "Usage: rake db:table_info[table_name]"
      exit 1
    end

    puts "Table Information: #{table_name}"
    puts "=" * 50

    size_query = <<-SQL
      SELECT
        pg_size_pretty(pg_total_relation_size('#{table_name}')) as total_size,
        pg_size_pretty(pg_relation_size('#{table_name}')) as table_size,
        pg_size_pretty(pg_indexes_size('#{table_name}')) as indexes_size
    SQL

    size_info = ActiveRecord::Base.connection.execute(size_query).first
    puts "Table size: #{size_info['table_size']}"
    puts "Indexes size: #{size_info['indexes_size']}"
    puts "Total size: #{size_info['total_size']}"

    count_query = "SELECT COUNT(*) as count FROM #{table_name}"
    row_count = ActiveRecord::Base.connection.execute(count_query).first['count']
    puts "Row count: #{row_count.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"

    index_query = <<-SQL
      SELECT
        indexname,
        pg_size_pretty(pg_relation_size(indexname::regclass)) as index_size
      FROM pg_indexes
      WHERE tablename = '#{table_name}'
      ORDER BY indexname
    SQL

    indexes = ActiveRecord::Base.connection.execute(index_query)
    puts "\nIndexes (#{indexes.count}):"
    indexes.each do |idx|
      puts "  - #{idx['indexname']} (#{idx['index_size']})"
    end
  end

  desc "Reset backtest database (for external PostgreSQL on port 6543)"
  task :reset_backtest do
    db_data_dir = ENV['DATABASE_DATA_DIR_DEV'] || File.expand_path('~/.options_trader/db')

    unless db_data_dir && !db_data_dir.strip.empty?
      puts "Error: Please set DATABASE_DATA_DIR_DEV environment variable to the PostgreSQL data directory"
      puts "Example: export DATABASE_DATA_DIR_DEV='/path/to/your/data_directory'"
      exit 1
    end

    puts "Backtest Database Reset"
    puts "=" * 50
    puts "Data directory: #{db_data_dir}"
    puts ""
    puts "This will:"
    puts "  1. Stop PostgreSQL server"
    puts "  2. Remove database directory"
    puts "  3. Recreate database cluster"
    puts "  4. Start PostgreSQL server"
    puts "  5. Create user and database"
    puts "  6. Run migrations"
    puts ""
    print "Are you sure? (y/N): "
    response = STDIN.gets.chomp

    unless response.downcase == 'y'
      puts "Operation cancelled"
      exit 0
    end

    # Stop PostgreSQL if running
    puts "\nStopping PostgreSQL server..."
    system("pg_ctl -D #{db_data_dir} stop 2>/dev/null || true")
    sleep 1

    # Remove database directory
    puts "Removing database directory..."
    system("rm -rf #{db_data_dir}")

    # Initialize new database cluster
    puts "Initializing new database cluster..."
    unless system("initdb -D #{db_data_dir} --auth-local=trust --auth-host=trust")
      puts "Error: Failed to initialize database cluster"
      exit 1
    end

    File.open("#{db_data_dir}/postgresql.conf", 'a') do |f|
      f.puts "port = 6543"
      f.puts "listen_addresses = 'localhost'"
    end

    pg_hba_path = "#{db_data_dir}/pg_hba.conf"
    pg_hba_content = File.read(pg_hba_path)
    pg_hba_content.gsub!(/host\s+all\s+all\s+127\.0\.0\.1\/32\s+\w+/, 'host    all             all             127.0.0.1/32            trust')
    pg_hba_content.gsub!(/host\s+all\s+all\s+::1\/128\s+\w+/, 'host    all             all             ::1/128                 trust')
    File.write(pg_hba_path, pg_hba_content)

    puts "Starting PostgreSQL server..."
    unless system("pg_ctl -D #{db_data_dir} -l #{db_data_dir}/log start")
      puts "Error: Failed to start PostgreSQL"
      exit 1
    end
    sleep 2

    puts "Creating user and database..."
    system("psql -h localhost -p 6543 -d postgres -c \"CREATE USER options_trader;\" 2>/dev/null || true")
    system("psql -h localhost -p 6543 -d postgres -c \"CREATE DATABASE options_trader_db OWNER options_trader;\"")
    system("psql -h localhost -p 6543 -d options_trader_db -c \"GRANT ALL PRIVILEGES ON DATABASE options_trader_db TO options_trader; GRANT ALL PRIVILEGES ON SCHEMA public TO options_trader;\"")
    system("psql -h localhost -p 6543 -d options_trader_db -c \"GRANT pg_checkpoint TO options_trader;\"")  # Allow checkpoints for data safety

    # Run migrations in development environment
    puts "Running migrations..."
    ENV['RAILS_ENV'] = 'development'
    ENV['RACK_ENV'] = 'development'

    # Load environment and run migrations
    require_relative '../../config/environment'
    ActiveRecord::Base.connection_pool.disconnect!
    ActiveRecord::MigrationContext.new("db/migrate").migrate

    puts "\n" + "=" * 50
    puts "Backtest database reset completed successfully!"
    puts "Database: options_trader_db"
    puts "Host: localhost"
    puts "Port: 6543"
    puts "Data directory: #{db_data_dir}"
    puts ""
    puts "To use this database, run commands with:"
    puts "  RAILS_ENV=development RACK_ENV=development"
  end

  desc "Generate a new migration file"
  task :migration, [:name] do |t, args|
    name = args[:name]
    unless name
      puts "Usage: rake db:migration[name]"
      exit 1
    end

    unless name.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)
      puts "Error: Invalid migration name. Use only letters, numbers, and underscores."
      puts "Migration names must start with a letter or underscore."
      exit 1
    end

    timestamp = Time.now.strftime("%Y%m%d%H%M%S")
    filename = "#{timestamp}_#{name.downcase}.rb"
    filepath = "db/migrate/#{filename}"

    class_name = name.split('_').map(&:capitalize).join

    migration_content = <<~RUBY
      class #{class_name} < ActiveRecord::Migration[8.0]
        def change
          # Add your migration code here
        end
      end
    RUBY

    File.write(filepath, migration_content)
    puts "Created migration: #{filepath}"
  end
end