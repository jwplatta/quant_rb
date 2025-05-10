# frozen_string_literal: true

require 'active_record'

module Persistence
  class Trade < ActiveRecord::Base
    self.table_name = 'trades'

    has_many :legs, class_name: 'Persistence::TradeLeg', foreign_key: 'trade_id'
    has_many :orders, class_name: 'Persistence::Order', foreign_key: 'trade_id'
    has_many :transactions, through: :orders, class_name: 'Persistence::Transaction'

    validates :underlying, presence: true
    validates :strategy, presence: true
    validates :open_date, presence: true
  end
end
