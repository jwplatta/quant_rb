require "active_record"
require "dotenv"

Dotenv.load

ActiveRecord::Base.establish_connection(
  adapter: "postgresql",
  database: ENV["DATABASE_NAME"],
  username: ENV["DATABASE_USER"],
  password: ENV["DATABASE_PASSWORD"],
  host: "localhost"
)

ActiveRecord::Schema.define do
  create_table :trades, force: true do |t|
    t.string :underlying, null: false
    t.string :strategy_type, null: false
    t.date :open_date, null: false
    t.date :close_date

    t.timestamps
  end

  create_table :orders, force: true do |t|
    t.string :order_id, null: false
    t.string :order_type, null: false
    t.string :underlying, null: false
    t.string :status, null: false
    t.string :strategy_type, null: false
    t.boolean :adjustment, default: false
    t.decimal :net_amount, default: 0.0
    t.references :trade, foreign_key: true

    t.timestamps
  end

  create_table :transactions, force: true do |t|
    t.string :symbol, null: false
    t.string :description, null: false
    t.string :put_call, null: false
    t.datetime :trade_date, null: false
    t.integer :instrument_id, null: false
    t.integer :quantity, default: 0
    t.decimal :fees, default: 0.0
    t.decimal :commission, default: 0.0
    t.decimal :cost, default: 0.0
    t.decimal :net_amount, default: 0.0
    t.string :position_effect, null: false
    t.references :order, foreign_key: true

    t.timestamps
  end
end

puts "✅ Database schema has been set up successfully!"
