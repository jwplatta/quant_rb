class BackfillSourceData < ActiveRecord::Migration[8.0]
  def up
    # Backfill source column with default value for existing records
    # Assuming existing data came from a specific source (e.g., 'polygon', 'schwab', etc.)
    execute <<-SQL
      UPDATE option_chain_history 
      SET source = 'polygon'
      WHERE source IS NULL
    SQL
    
    puts "Backfilled #{connection.execute('SELECT COUNT(*) FROM option_chain_history WHERE source = \'polygon\'').first['count']} records with source = 'polygon'"
  end

  def down
    # Optionally clear the backfilled source data
    execute "UPDATE option_chain_history SET source = NULL WHERE source = 'polygon'"
  end
end
