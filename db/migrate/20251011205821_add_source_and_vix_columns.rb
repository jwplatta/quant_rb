class AddSourceAndVixColumns < ActiveRecord::Migration[8.0]
  def change
    add_column :option_chain_history, :source, :string, null: true
    add_column :option_chain_history, :vix, :decimal, precision: 6, scale: 2, null: true
    add_column :option_chain_history, :vix9d, :decimal, precision: 6, scale: 2, null: true
    add_column :option_chain_history, :vix3m, :decimal, precision: 6, scale: 2, null: true
    add_column :option_chain_history, :vvix, :decimal, precision: 6, scale: 2, null: true
    add_column :option_chain_history, :skew, :decimal, precision: 6, scale: 2, null: true
  end
end
