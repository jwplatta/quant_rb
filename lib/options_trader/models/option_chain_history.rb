require_relative 'base'

module OptionsTrader
  class OptionChainHistory < Base
    self.table_name = 'option_chain_history'

    validates :symbol, presence: true
    validates :underlying_symbol, presence: true
    validates :expiration_date, presence: true
    validates :strike, presence: true, numericality: { greater_than: 0 }
    validates :contract_type, presence: true, inclusion: { in: %w[PUT CALL] }
    validates :valid_time, presence: true
    validates :transaction_time, presence: true
    validates :underlying_price, numericality: { greater_than: 0 }, allow_nil: true
    validates :expiration_type, inclusion: { in: %w[W S M Q] }, allow_nil: true
    validates :volatility, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

    scope :calls, -> { where(contract_type: 'CALL') }
    scope :puts, -> { where(contract_type: 'PUT') }
    scope :for_underlying, ->(symbol) { where(underlying_symbol: symbol) }
    scope :for_expiration, ->(date) { where(expiration_date: date) }
    scope :for_strike, ->(strike_price) { where(strike: strike_price) }
    scope :at_time, ->(time) { where('valid_time <= ?', time).order(valid_time: :desc) }
    scope :recent_first, -> { order(transaction_time: :desc, valid_time: :desc) }

    def self.latest_for_contract(symbol, expiration_date, strike, contract_type, at_time = Time.current)
      where(
        symbol: symbol,
        expiration_date: expiration_date,
        strike: strike,
        contract_type: contract_type
      )
      .at_time(at_time)
      .first
    end

    def self.for_underlying_at_time(underlying_symbol, at_time = Time.current)
      for_underlying(underlying_symbol)
        .at_time(at_time)
        .group(:symbol, :expiration_date, :strike, :contract_type)
        .select('DISTINCT ON (symbol, expiration_date, strike, contract_type) *')
        .order(:symbol, :expiration_date, :strike, :contract_type, valid_time: :desc)
    end

    def call?
      contract_type == 'CALL'
    end

    def put?
      contract_type == 'PUT'
    end

    def in_the_money?(underlying_price)
      if call?
        underlying_price > strike
      else
        underlying_price < strike
      end
    end

    def moneyness(underlying_price)
      if call?
        underlying_price - strike
      else
        strike - underlying_price
      end
    end

    def mid_price
      return nil unless bid && ask
      (bid + ask) / 2.0
    end

    def spread
      return nil unless bid && ask
      ask - bid
    end

    def days_to_expiration(from_date = Date.current)
      (expiration_date.to_date - from_date).to_i
    end

    def weekly_expiration?
      expiration_type == 'W'
    end

    def monthly_expiration?
      expiration_type == 'M'
    end

    def quarterly_expiration?
      expiration_type == 'Q'
    end

    def special_expiration?
      expiration_type == 'S'
    end

    def spread_percentage
      return nil unless bid && ask && mid_price && mid_price > 0
      (spread / mid_price) * 100
    end

    def last_vs_mid
      return nil unless last_price && mid_price
      last_price - mid_price
    end

    def volume_to_open_interest_ratio
      return nil unless volume && open_interest && open_interest > 0
      volume.to_f / open_interest
    end

    def price_range_percentage
      return nil unless high_price && low_price && low_price > 0
      ((high_price - low_price) / low_price) * 100
    end
  end
end