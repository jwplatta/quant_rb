class CreatePriceHistory < ActiveRecord::Migration[8.0]
  def change
    create_table :price_history do |t|
      t.string :symbol, null: false, index: true
      t.decimal :open, precision: 10, scale: 2
      t.decimal :close, precision: 10, scale: 2
      t.decimal :high, precision: 10, scale: 2
      t.decimal :low, precision: 10, scale: 2
      t.integer :volume, null: false, default: 0
      t.string :interval, null: false
      t.timestamp :valid_time, null: false, index: true
      t.timestamps null: false
    end

    add_index :price_history, [:symbol, :valid_time, :interval], unique: true, name: 'index_price_history_on_symbol_and_time_and_interval'

    add_check_constraint :price_history, 'open >= 0', name: 'positive_open'
    add_check_constraint :price_history, 'close >= 0', name: 'positive_close'
    add_check_constraint :price_history, 'high >= 0', name: 'positive_high'
    add_check_constraint :price_history, 'low >= 0', name: 'positive_low'
    add_check_constraint :price_history, 'high >= low', name: 'high_gte_low'
    add_check_constraint :price_history, 'volume >= 0', name: 'non_negative_volume'
  end
end
