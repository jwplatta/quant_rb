require "active_record"

module Persistence
  class TradeLeg < ActiveRecord::Base
    self.table_name = 'trade_legs'

    belongs_to :trade, class_name: 'Persistence::Trade'

    validates :put_call, presence: true
    validates :symbol, presence: true
    validates :mark, presence: true
    validates :ask, presence: true
    validates :bid, presence: true
    validates :delta, presence: true
    validates :expiration_date, presence: true
    validates :instruction, presence: true
  end
end