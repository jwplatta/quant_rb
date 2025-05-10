# frozen_string_literal: true

require 'active_record'

module Persistence
  class Order < ActiveRecord::Base
    self.table_name = 'orders'

    belongs_to :trade, class_name: 'Persistence::Trade'
    has_many :transactions, class_name: 'Persistence::Transaction', foreign_key: 'order_id'

    validates :order_id, presence: true
    validates :order_type, presence: true
    validates :underlying, presence: true
    validates :status, presence: true
    validates :strategy_type, presence: true
  end
end
