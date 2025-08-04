# frozen_string_literal: true

require 'spec_helper'

RSpec.describe OptionsTrader::OptionChainHistory, type: :model do
  # NOTE: Database connection handled by config/environment.rb via spec_helper.rb

  describe 'database connection' do
    it 'successfully connects to test database' do
      expect(ActiveRecord::Base.connection).to be_present
      expect(ActiveRecord::Base.connection.current_database).to eq('options_trader_db_test')
    end

    it 'can perform basic database operations' do
      expect { described_class.count }.not_to raise_error
    end
  end

  describe '5-minute time bucket queries' do
    let(:underlying_symbol) { '$SPX' }
    let(:spx_call_symbol) { 'SPXW250810C06410' }
    let(:spx_put_symbol) { 'SPXW250810P06410' }
    let(:call_expiration) { Date.parse('2025-08-10') }
    let(:call_strike) { 6410.00 }

    before do
      # Clean up any existing test data for this specific contract
      described_class.where(symbol: spx_call_symbol).delete_all

      # Create 5-minute time bucket data points using FactoryBot
      # August 1st - 5-minute aligned timestamps
      create(:spx_6410_call, valid_time: Time.parse('2025-08-01 09:45:00'),
             mark: 125.50, bid: 124.20, ask: 126.80, last_price: 125.00,
             underlying_price: 6532.15, delta: 0.64, theta: -2.47, vega: 8.95,
             gamma: 0.0046, rho: 0.14, volume: 12)

      create(:spx_6410_put, valid_time: Time.parse('2025-08-01 09:45:00'),
             mark: 126.75, bid: 125.50, ask: 127.00, last_price: 126.25,
             underlying_price: 6535.60, delta: -0.63, theta: -2.48, vega: 8.90,
             gamma: 0.0045, rho: 0.15, volume: 18)

      create(:spx_6410_call, valid_time: Time.parse('2025-08-01 10:00:00'),
             mark: 127.00, bid: 125.80, ask: 128.20, last_price: 126.50,
             underlying_price: 6538.92, delta: 0.65, theta: -2.46, vega: 8.92,
             gamma: 0.0045, rho: 0.15, volume: 28)

      create(:spx_6410_put, valid_time: Time.parse('2025-08-01 10:00:00'),
             mark: 128.50, bid: 127.30, ask: 129.70, last_price: 128.00,
             underlying_price: 6542.10, delta: -0.64, theta: -2.45,
             vega: 8.89, gamma: 0.0044, rho: 0.16,
             volume: 35)

      create(:spx_6410_call, valid_time: Time.parse('2025-08-01 10:05:00'),
             mark: 128.50, bid: 127.40, ask: 129.60, last_price: 128.25,
             underlying_price: 6544.33, delta: 0.66, theta: -2.44, vega: 8.88,
             gamma: 0.0044, rho: 0.16, volume: 41)

      create(:spx_6410_call, valid_time: Time.parse('2025-08-01 14:00:00'),
             mark: 130.25, bid: 129.10, ask: 131.40, last_price: 129.80,
             underlying_price: 6548.76, delta: 0.67, theta: -2.42, vega: 8.84,
             gamma: 0.0043, rho: 0.17, volume: 58)

      create(:spx_6410_call, valid_time: Time.parse('2025-08-01 14:05:00'),
             mark: 132.05, bid: 130.90, ask: 133.20, last_price: 131.60,
             underlying_price: 6552.41, delta: 0.68, theta: -2.40, vega: 8.81,
             gamma: 0.0042, rho: 0.18, volume: 73)

      # August 4th data points
      create(:spx_6410_call, valid_time: Time.parse('2025-08-04 09:30:00'),
             mark: 133.35, bid: 132.10, ask: 134.60, last_price: 133.00,
             underlying_price: 6548.92, delta: 0.67, theta: -2.38, vega: 8.76,
             gamma: 0.0043, rho: 0.17, volume: 89, open_interest: 1245)

      create(:spx_6410_call, valid_time: Time.parse('2025-08-04 15:45:00'),
             mark: 137.00, bid: 135.80, ask: 138.20, last_price: 136.45,
             underlying_price: 6555.33, delta: 0.68, theta: -2.35, vega: 8.69,
             gamma: 0.0042, rho: 0.18, volume: 112, open_interest: 1245)
    end

    after do
      described_class.where(symbol: spx_call_symbol).delete_all
      described_class.where(symbol: spx_put_symbol).delete_all
    end

    it 'retrieves exact time bucket data at 10:00 AM on August 1st' do
      time_bucket = Time.parse('2025-08-01 10:00:00')

      option = described_class
        .where(symbol: spx_call_symbol, expiration_date: call_expiration)
        .where(valid_time: time_bucket)

      expect(option.count).to eq(1)
      record = option.first

      expect(record.mark).to eq(127.00)
      expect(record.underlying_price).to eq(6538.92)
      expect(record.delta).to eq(0.65)
      expect(record.strike).to eq(6410.00)
      expect(record.contract_type).to eq('CALL')
    end

    it 'queries within a 5-minute time bucket window' do
      # Query for data within the 10:00-10:05 AM time bucket
      start_time = Time.parse('2025-08-01 10:00:00')
      end_time = Time.parse('2025-08-01 10:04:59')

      options = described_class
        .where(symbol: spx_call_symbol, expiration_date: call_expiration)
        .where('valid_time BETWEEN ? AND ?', start_time, end_time)

      expect(options.count).to eq(1)
      record = options.first

      expect(record.mark).to eq(127.00)
      expect(record.valid_time).to eq(Time.parse('2025-08-01 10:00:00'))
    end

    it 'tracks price evolution across multiple 5-minute time buckets' do
      # Get all August 1st 5-minute time buckets for this contract
      start_of_day = Time.parse('2025-08-01 00:00:00')
      end_of_day = Time.parse('2025-08-01 23:59:59')

      daily_records = described_class
        .where(symbol: spx_call_symbol, expiration_date: call_expiration)
        .where('valid_time BETWEEN ? AND ?', start_of_day, end_of_day)
        .order(valid_time: :asc)

      expect(daily_records.count).to eq(5)

      daily_prices = daily_records.pluck(:valid_time, :mark, :underlying_price, :delta)

      # Verify 5-minute aligned timestamps
      timestamps = daily_prices.map { |time, _, _, _| time }
      expect(timestamps).to eq([
        Time.parse('2025-08-01 09:45:00'),
        Time.parse('2025-08-01 10:00:00'),
        Time.parse('2025-08-01 10:05:00'),
        Time.parse('2025-08-01 14:00:00'),
        Time.parse('2025-08-01 14:05:00')
      ])

      # Verify price progression
      marks = daily_prices.map { |_, mark, _, _| mark }
      expect(marks).to eq([125.50, 127.00, 128.50, 130.25, 132.05])

      # Verify underlying progression
      underlyings = daily_prices.map { |_, _, underlying, _| underlying }
      expect(underlyings.first).to eq(6532.15)
      expect(underlyings.last).to eq(6552.41)

      # Verify delta progression
      deltas = daily_prices.map { |_, _, _, delta| delta }
      expect(deltas).to eq([0.64, 0.65, 0.66, 0.67, 0.68])
    end

    fit 'reconstructs option chain history for specific expiration date' do
      start_time = Time.parse('2025-08-01 10:00:00')
      end_time = Time.parse('2025-08-01 10:04:59')
      expiration_date = Date.parse('2025-08-10')

      daily_records = described_class
        .where(underlying_symbol: underlying_symbol, expiration_date: expiration_date)
        .where('valid_time BETWEEN ? AND ?', start_time, end_time)
        .order(valid_time: :asc)

      expect(daily_records.count).to eq(2)
    end
  end
end
