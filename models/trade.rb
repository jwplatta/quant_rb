require "active_record"

class CreateTrade < ActiveRecord::Base
  has_many :orders
  has_many :transactions, through: :orders

  validates :underlying, presence: true
  validates :strategy, presence: true
  validates :open_date, presence: true
end
