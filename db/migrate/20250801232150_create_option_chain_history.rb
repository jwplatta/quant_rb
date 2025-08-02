class CreateOptionChainHistory < ActiveRecord::Migration[8.0]
  def change
    create_table :option_chain_history do |t|
      # Contract identification
      t.string :symbol, null: false, index: true
      t.string :root_symbol
      t.string :underlying_symbol, null: false, index: true
      t.date :expiration_date, null: false, index: true
      t.decimal :strike, precision: 10, scale: 2, null: false, index: true
      t.string :contract_type, null: false, index: true
      
      # Pricing data
      t.decimal :bid, precision: 10, scale: 4
      t.decimal :ask, precision: 10, scale: 4
      t.decimal :mark, precision: 10, scale: 4
      t.decimal :last_price, precision: 10, scale: 4
      
      # Underlying data
      t.decimal :underlying_price, precision: 10, scale: 4
      
      # Greeks
      t.decimal :delta, precision: 8, scale: 6
      t.decimal :theta, precision: 8, scale: 6
      t.decimal :vega, precision: 8, scale: 6
      t.decimal :gamma, precision: 8, scale: 6
      t.decimal :rho, precision: 8, scale: 6
      
      # Volume/Interest
      t.integer :open_interest
      t.integer :volume
      t.integer :bid_size
      t.integer :ask_size
      
      # Option data
      t.string :option_root
      t.string :expiration_type
      t.decimal :intrinsic_value, precision: 10, scale: 4
      t.decimal :extrinsic_value, precision: 10, scale: 4
      t.decimal :time_value, precision: 10, scale: 4
      t.decimal :volatility, precision: 8, scale: 6
      
      # Price history
      t.decimal :high_52_week, precision: 10, scale: 4
      t.decimal :low_52_week, precision: 10, scale: 4
      t.decimal :high_price, precision: 10, scale: 4
      t.decimal :low_price, precision: 10, scale: 4
      t.decimal :open_price, precision: 10, scale: 4
      t.decimal :close_price, precision: 10, scale: 4
      
      # Bitemporal timestamps
      t.timestamp :valid_time, null: false, index: true
      t.timestamp :transaction_time, null: false, default: -> { 'CURRENT_TIMESTAMP' }, index: true
    end
    
    # Composite indexes for efficient querying
    add_index :option_chain_history, [:underlying_symbol, :expiration_date, :valid_time]
    add_index :option_chain_history, [:symbol, :valid_time]
    add_index :option_chain_history, [:underlying_symbol, :contract_type, :valid_time]
    add_index :option_chain_history, [:expiration_date, :strike, :contract_type, :valid_time]
    
    # Constraint to ensure contract_type is either PUT or CALL
    add_check_constraint :option_chain_history, "contract_type IN ('PUT', 'CALL')", name: 'valid_contract_type'
    
    # Constraint to ensure strike is positive
    add_check_constraint :option_chain_history, 'strike > 0', name: 'positive_strike'
  end
end
