require_relative 'base'

module OptionsTrader
  class PriceHistory < Base
    self.table_name = 'price_history'

    validates :symbol, presence: true
    validates :open, :close, :high, :low, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :volume, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :interval, presence: true
    validates :valid_time, presence: true

    validate :high_greater_than_or_equal_to_low

    scope :for_symbol, ->(symbol) { where(symbol: symbol) }
    scope :for_interval, ->(interval) { where(interval: interval) }
    scope :between_dates, ->(start_date, end_date) { where(valid_time: start_date..end_date) }

    def self.latest_for_symbol(symbol, end_time, start_time = nil, interval = '5min')
      query = for_symbol(symbol).where('valid_time <= ?', end_time)
      query = query.where('valid_time > ?', start_time) if start_time
      query = query.for_interval(interval) if interval
      query.order(valid_time: :desc).first
    end

    private

    def high_greater_than_or_equal_to_low
      return unless high && low

      errors.add(:high, 'must be greater than or equal to low') if high < low
    end
  end
end
