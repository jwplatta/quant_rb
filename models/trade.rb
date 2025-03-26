require "active_record"

module DB
  class Trade < ActiveRecord::Base
    self.table_name = 'trades'
    
    has_many :legs, class_name: 'DB::TradeLeg', foreign_key: 'trade_id'
    has_many :orders, class_name: 'DB::Order', foreign_key: 'trade_id'
    has_many :transactions, through: :orders, class_name: 'DB::Transaction'

    validates :underlying, presence: true
    validates :strategy, presence: true
    validates :open_date, presence: true
  end
end
