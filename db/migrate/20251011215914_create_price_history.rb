class CreatePriceHistory < ActiveRecord::Migration[8.0]
  def change
    create_table :price_history do |t|
      t.string :symbol, null: false, index: true
      t.decimal :open, precision: 10, scale: 2
      t.decimal :close, precision: 10, scale: 2
      t.decimal :high, precision: 10, scale: 2
      t.decimal :low, precision: 10, scale: 2
      t.integer :volume
      t.timestamp :valid_time, null: false, index: true
      t.timestamp :transaction_time, null: false, default: -> { 'CURRENT_TIMESTAMP' }, index: true
    end

    add_index :price_history, [:symbol, :valid_time]

    add_check_constraint :price_history, 'open >= 0', name: 'positive_open'
    add_check_constraint :price_history, 'close >= 0', name: 'positive_close'
    add_check_constraint :price_history, 'high >= 0', name: 'positive_high'
    add_check_constraint :price_history, 'low >= 0', name: 'positive_low'

    add_check_constraint :price_history, 'high >= low', name: 'high_gte_low'

    add_check_constraint :price_history, 'volume >= 0', name: 'non_negative_volume'
  end
end
