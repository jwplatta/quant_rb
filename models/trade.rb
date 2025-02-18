require "active_record"

class Trade < ActiveRecord::Base
  has_many :legs
  has_many :orders
  has_many :transactions, through: :orders

  validates :underlying, presence: true
  validates :strategy_type, presence: true
  validates :open_date, presence: true
end
