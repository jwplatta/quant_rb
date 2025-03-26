require "active_record"
require "fileutils"
require "yaml"
require "erb"
require "dotenv/load"

# Ensure the db directory exists
FileUtils.mkdir_p("db")

# Configure environment (development is default)
ENV["RACK_ENV"] ||= "development"

# Load database configuration from config/database.yml
db_config_file = File.expand_path("../../config/database.yml", __FILE__)
db_config = YAML.load(ERB.new(File.read(db_config_file)).result, aliases: true)

# Set up the database connection
ActiveRecord::Base.establish_connection(db_config[ENV["RACK_ENV"]])

ActiveRecord::Schema.define do
  create_table :trades, force: true do |t|
    t.string :underlying, null: false
    t.string :strategy, null: false
    t.date :open_date, null: false
    t.date :close_date

    t.timestamps
  end

  create_table :trade_legs, force: true do |t|
    t.string :put_call, null: false
    t.string :symbol, null: false
    t.decimal :mark, null: false
    t.decimal :ask, null: false
    t.decimal :bid, null: false
    t.decimal :delta, null: false
    t.decimal :strike, default: 0.0
    t.date :expiration_date, null: false
    t.string :instruction, null: false
    t.integer :quantity, default: 1
    t.references :trade, foreign_key: true

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
