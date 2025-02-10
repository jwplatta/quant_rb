namespace :db do
  desc "Run migrations"
  task :migrate do
    ActiveRecord::Migrator.migrations_paths = ["db/migrations"]
    ActiveRecord::MigrationContext.new(
      ActiveRecord::Migrator.migrations_paths,
      ActiveRecord::Base.connection.schema_migration
    ).migrate
    puts "✅ Migrations applied!"
  end

  desc "Create a new migration"
  task :create_migration, [:name] do |t, args|
    name = args[:name] || "new_migration"
    timestamp = Time.now.strftime("%Y%m%d%H%M%S")
    filename = "db/migrations/#{timestamp}_#{name}.rb"

    migration_template = <<-MIGRATION
      class #{name.split('_').map(&:capitalize).join} < ActiveRecord::Migration[6.1]
        def change
          # Define your migration here
        end
      end
    MIGRATION

    File.write(filename, migration_template)
    puts "✅ Created migration: #{filename}"
  end
end
