class CreateOptionChainHistory < ActiveRecord::Migration[8.0]
  def change
    create_table :option_chain_history do |t|
      t.string :symbol, null: false, index: true
      t.string :root_symbol, null: false, index: true
      t.string :underlying_symbol, null: false, index: true
      t.date :expiration_date, null: false, index: true
      t.decimal :strike, precision: 10, scale: 2, null: false, index: true
      t.string :contract_type, null: false, index: true

      t.decimal :bid, precision: 10, scale: 2
      t.decimal :ask, precision: 10, scale: 2
      t.decimal :mark, precision: 10, scale: 2
      t.decimal :last_price, precision: 10, scale: 2

      t.decimal :underlying_price, precision: 10, scale: 2

      t.decimal :delta, precision: 10, scale: 2
      t.decimal :theta, precision: 10, scale: 2
      t.decimal :vega, precision: 10, scale: 2
      t.decimal :gamma, precision: 10, scale: 2
      t.decimal :rho, precision: 10, scale: 2

      t.integer :open_interest
      t.integer :volume
      t.integer :bid_size
      t.integer :ask_size

      t.string :expiration_type
      t.decimal :intrinsic_value, precision: 10, scale: 2
      t.decimal :extrinsic_value, precision: 10, scale: 2
      t.decimal :time_value, precision: 10, scale: 2
      t.decimal :volatility, precision: 10, scale: 2

      t.decimal :high_52_week, precision: 10, scale: 2
      t.decimal :low_52_week, precision: 10, scale: 2
      t.decimal :high_price, precision: 10, scale: 2
      t.decimal :low_price, precision: 10, scale: 2
      t.decimal :open_price, precision: 10, scale: 2
      t.decimal :close_price, precision: 10, scale: 2

      t.string :source, null: true, index: true

      t.timestamp :valid_time, null: false, index: true
      t.timestamp :transaction_time, null: false, default: -> { 'CURRENT_TIMESTAMP' }, index: true
      t.timestamps null: false
    end

    add_check_constraint :option_chain_history, "contract_type IN ('PUT', 'CALL')", name: 'valid_contract_type'
    add_check_constraint :option_chain_history, 'strike > 0', name: 'positive_strike'
  end
end
