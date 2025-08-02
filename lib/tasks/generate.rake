namespace :generate do
  desc "Generate a new migration file"
  task :migration do
    name = ENV['NAME']
    unless name
      puts "Usage: rake generate:migration NAME=migration_name"
      exit 1
    end
    
    # Validate migration name to prevent SQL injection and ensure valid Ruby class names
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