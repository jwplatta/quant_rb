require "active_record"

module DB
  class Transaction < ActiveRecord::Base
    self.table_name = 'transactions'
    
    belongs_to :order, class_name: 'DB::Order'

    validates :symbol, presence: true
    validates :description, presence: true
    validates :put_call, presence: true
    validates :trade_date, presence: true
    validates :instrument_id, presence: true
    validates :quantity, presence: true
    validates :fees, presence: true
    validates :commission, presence: true
    validates :cost, presence: true
    validates :net_amount, presence: true
    validates :position_effect, presence: true
  end
end
