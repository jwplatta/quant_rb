class AddBacktestIndexesAndConstraints < ActiveRecord::Migration[8.0]
  def change
    # Add index on root_symbol and valid_time for efficient backtest queries
    add_index :option_chain_history, [:root_symbol, :valid_time], name: 'index_option_chain_history_on_root_symbol_and_valid_time'
    
    # Add index on symbol column for fast symbol lookups
    # Note: symbol already has an index from the original migration, but adding explicit name for clarity
    # This will be skipped if index already exists
    add_index :option_chain_history, :symbol, name: 'index_option_chain_history_on_symbol', if_not_exists: true
    
    # Add unique constraint on composite key for data integrity
    # This ensures no duplicate records for the same contract at the same time
    add_index :option_chain_history, 
              [:root_symbol, :expiration_date, :strike, :contract_type, :valid_time], 
              unique: true, 
              name: 'unique_option_chain_history_composite'
  end
end
