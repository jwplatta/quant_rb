require "active_record"

class Order < ActiveRecord::Base
  belongs_to :trade
  has_many :transactions

  validates :order_id, presence: true
  validates :underlying, presence: true
  validates :status, presence: true
  validates :trade_type, presence: true
  validates :underlying, presence: true
end
