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
    let(:root_symbol) { 'SPXW' }
    let(:spx_call_symbol) { 'SPXW250810C06410' }
    let(:spx_put_symbol) { 'SPXW250810P06410' }
    let(:call_expiration) { Date.parse('2025-08-10') }
    let(:call_strike) { 6410.00 }

    before do
      # Clean up any existing test data for this specific contract
      described_class.where(symbol: spx_call_symbol).delete_all

      # Create 5-minute time bucket data points directly
      # August 1st - 5-minute aligned timestamps
      described_class.create!(
        symbol: spx_call_symbol,
        root_symbol: root_symbol,
        underlying_symbol: underlying_symbol,
        expiration_date: call_expiration,
        strike: call_strike,
        contract_type: 'CALL',
        valid_time: Time.parse('2025-08-01 09:45:00'),
        transaction_time: Time.parse('2025-08-01 09:45:00'),
        mark: 125.50, bid: 124.20, ask: 126.80, last_price: 125.00,
        underlying_price: 6532.15, delta: 0.64, theta: -2.47, vega: 8.95,
        gamma: 0.0046, rho: 0.14, volume: 12,
        source: 'polygon'
      )

      described_class.create!(
        symbol: spx_put_symbol,
        root_symbol: root_symbol,
        underlying_symbol: underlying_symbol,
        expiration_date: call_expiration,
        strike: call_strike,
        contract_type: 'PUT',
        valid_time: Time.parse('2025-08-01 09:45:00'),
        transaction_time: Time.parse('2025-08-01 09:45:00'),
        mark: 126.75, bid: 125.50, ask: 127.00, last_price: 126.25,
        underlying_price: 6535.60, delta: -0.63, theta: -2.48, vega: 8.90,
        gamma: 0.0045, rho: 0.15, volume: 18,
        source: 'polygon'
      )

      described_class.create!(
        symbol: spx_call_symbol,
        root_symbol: root_symbol,
        underlying_symbol: underlying_symbol,
        expiration_date: call_expiration,
        strike: call_strike,
        contract_type: 'CALL',
        valid_time: Time.parse('2025-08-01 10:00:00'),
        transaction_time: Time.parse('2025-08-01 10:00:00'),
        mark: 127.00, bid: 125.80, ask: 128.20, last_price: 126.50,
        underlying_price: 6538.92, delta: 0.65, theta: -2.46, vega: 8.92,
        gamma: 0.0045, rho: 0.15, volume: 28,
        source: 'polygon'
      )

      described_class.create!(
        symbol: spx_put_symbol,
        root_symbol: root_symbol,
        underlying_symbol: underlying_symbol,
        expiration_date: call_expiration,
        strike: call_strike,
        contract_type: 'PUT',
        valid_time: Time.parse('2025-08-01 10:00:00'),
        transaction_time: Time.parse('2025-08-01 10:00:00'),
        mark: 128.50, bid: 127.30, ask: 129.70, last_price: 128.00,
        underlying_price: 6542.10, delta: -0.64, theta: -2.45,
        vega: 8.89, gamma: 0.0044, rho: 0.16,
        volume: 35,
        source: 'polygon'
      )

      described_class.create!(
        symbol: spx_call_symbol,
        root_symbol: root_symbol,
        underlying_symbol: underlying_symbol,
        expiration_date: call_expiration,
        strike: call_strike,
        contract_type: 'CALL',
        valid_time: Time.parse('2025-08-01 10:05:00'),
        transaction_time: Time.parse('2025-08-01 10:05:00'),
        mark: 128.50, bid: 127.40, ask: 129.60, last_price: 128.25,
        underlying_price: 6544.33, delta: 0.66, theta: -2.44, vega: 8.88,
        gamma: 0.0044, rho: 0.16, volume: 41,
        source: 'polygon'
      )

      described_class.create!(
        symbol: spx_call_symbol,
        root_symbol: root_symbol,
        underlying_symbol: underlying_symbol,
        expiration_date: call_expiration,
        strike: call_strike,
        contract_type: 'CALL',
        valid_time: Time.parse('2025-08-01 14:00:00'),
        transaction_time: Time.parse('2025-08-01 14:00:00'),
        mark: 130.25, bid: 129.10, ask: 131.40, last_price: 129.80,
        underlying_price: 6548.76, delta: 0.67, theta: -2.42, vega: 8.84,
        gamma: 0.0043, rho: 0.17, volume: 58,
        source: 'polygon'
      )

      described_class.create!(
        symbol: spx_call_symbol,
        root_symbol: root_symbol,
        underlying_symbol: underlying_symbol,
        expiration_date: call_expiration,
        strike: call_strike,
        contract_type: 'CALL',
        valid_time: Time.parse('2025-08-01 14:05:00'),
        transaction_time: Time.parse('2025-08-01 14:05:00'),
        mark: 132.05, bid: 130.90, ask: 133.20, last_price: 131.60,
        underlying_price: 6552.41, delta: 0.68, theta: -2.40, vega: 8.81,
        gamma: 0.0042, rho: 0.18, volume: 73,
        source: 'polygon'
      )

      # August 4th data points
      described_class.create!(
        symbol: spx_call_symbol,
        root_symbol: root_symbol,
        underlying_symbol: underlying_symbol,
        expiration_date: call_expiration,
        strike: call_strike,
        contract_type: 'CALL',
        valid_time: Time.parse('2025-08-04 09:30:00'),
        transaction_time: Time.parse('2025-08-04 09:30:00'),
        mark: 133.35, bid: 132.10, ask: 134.60, last_price: 133.00,
        underlying_price: 6548.92, delta: 0.67, theta: -2.38, vega: 8.76,
        gamma: 0.0043, rho: 0.17, volume: 89, open_interest: 1245,
        source: 'polygon'
      )

      described_class.create!(
        symbol: spx_call_symbol,
        root_symbol: root_symbol,
        underlying_symbol: underlying_symbol,
        expiration_date: call_expiration,
        strike: call_strike,
        contract_type: 'CALL',
        valid_time: Time.parse('2025-08-04 15:45:00'),
        transaction_time: Time.parse('2025-08-04 15:45:00'),
        mark: 137.00, bid: 135.80, ask: 138.20, last_price: 136.45,
        underlying_price: 6555.33, delta: 0.68, theta: -2.35, vega: 8.69,
        gamma: 0.0042, rho: 0.18, volume: 112, open_interest: 1245,
        source: 'polygon'
      )
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

    it 'reconstructs option chain history for specific expiration date' do
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

  describe '.fetch_with_locf' do
    let(:underlying_symbol) { '$SPX' }
    let(:expiration_date) { Date.parse('2025-08-10') }
    let(:end_time) { Time.parse('2025-08-01 10:05:00 UTC') }

    before do
      # Clean up any existing test data
      described_class.where(underlying_symbol: underlying_symbol).delete_all
      OptionsTrader::PriceHistory.where(symbol: underlying_symbol).delete_all

      # Create price history data (for LOCF join)
      OptionsTrader::PriceHistory.create!(
        symbol: underlying_symbol,
        valid_time: Time.parse('2025-08-01 09:30:00 UTC'),
        open: 6520.00,
        high: 6525.00,
        low: 6518.00,
        close: 6522.50,
        volume: 1000,
        interval: '5min'
      )

      OptionsTrader::PriceHistory.create!(
        symbol: underlying_symbol,
        valid_time: Time.parse('2025-08-01 09:45:00 UTC'),
        open: 6522.50,
        high: 6535.00,
        low: 6522.00,
        close: 6532.15,
        volume: 1200,
        interval: '5min'
      )

      OptionsTrader::PriceHistory.create!(
        symbol: underlying_symbol,
        valid_time: Time.parse('2025-08-01 10:00:00 UTC'),
        open: 6532.15,
        high: 6540.00,
        low: 6530.00,
        close: 6538.92,
        volume: 1500,
        interval: '5min'
      )

      # Create option chain history data
      # Earlier data outside the window (should not be included)
      described_class.create!(
        symbol: 'SPXW250810C06400',
        root_symbol: 'SPXW',
        underlying_symbol: underlying_symbol,
        expiration_date: expiration_date,
        strike: 6400.00,
        contract_type: 'CALL',
        valid_time: Time.parse('2025-08-01 09:30:00 UTC'),
        transaction_time: Time.parse('2025-08-01 09:30:00 UTC'),
        mark: 130.00, bid: 128.00, ask: 132.00,
        underlying_price: 6522.50,
        source: 'polygon'
      )

      # Data within the 5-minute window
      described_class.create!(
        symbol: 'SPXW250810C06400',
        root_symbol: 'SPXW',
        underlying_symbol: underlying_symbol,
        expiration_date: expiration_date,
        strike: 6400.00,
        contract_type: 'CALL',
        valid_time: Time.parse('2025-08-01 10:01:00 UTC'),
        transaction_time: Time.parse('2025-08-01 10:01:00 UTC'),
        mark: 135.00, bid: 133.00, ask: 137.00,
        underlying_price: 6538.92,
        source: 'polygon'
      )

      # Multiple records for same symbol (LOCF should pick the most recent)
      described_class.create!(
        symbol: 'SPXW250810C06410',
        root_symbol: 'SPXW',
        underlying_symbol: underlying_symbol,
        expiration_date: expiration_date,
        strike: 6410.00,
        contract_type: 'CALL',
        valid_time: Time.parse('2025-08-01 10:02:00 UTC'),
        transaction_time: Time.parse('2025-08-01 10:02:00 UTC'),
        mark: 125.00, bid: 123.50, ask: 126.50,
        underlying_price: 6538.92,
        source: 'polygon'
      )

      described_class.create!(
        symbol: 'SPXW250810C06410',
        root_symbol: 'SPXW',
        underlying_symbol: underlying_symbol,
        expiration_date: expiration_date,
        strike: 6410.00,
        contract_type: 'CALL',
        valid_time: Time.parse('2025-08-01 10:04:00 UTC'),
        transaction_time: Time.parse('2025-08-01 10:04:00 UTC'),
        mark: 127.50, bid: 126.00, ask: 129.00,
        underlying_price: 6540.00,
        source: 'polygon'
      )

      # PUT option
      described_class.create!(
        symbol: 'SPXW250810P06400',
        root_symbol: 'SPXW',
        underlying_symbol: underlying_symbol,
        expiration_date: expiration_date,
        strike: 6400.00,
        contract_type: 'PUT',
        valid_time: Time.parse('2025-08-01 10:03:00 UTC'),
        transaction_time: Time.parse('2025-08-01 10:03:00 UTC'),
        mark: 140.00, bid: 138.50, ask: 141.50,
        underlying_price: 6538.92,
        source: 'polygon'
      )

      # Record with mark = 0 (should be filtered out)
      described_class.create!(
        symbol: 'SPXW250810C06420',
        root_symbol: 'SPXW',
        underlying_symbol: underlying_symbol,
        expiration_date: expiration_date,
        strike: 6420.00,
        contract_type: 'CALL',
        valid_time: Time.parse('2025-08-01 10:02:00 UTC'),
        transaction_time: Time.parse('2025-08-01 10:02:00 UTC'),
        mark: 0.00, bid: 0.00, ask: 0.00,
        underlying_price: 6538.92,
        source: 'polygon'
      )
    end

    after do
      described_class.where(underlying_symbol: underlying_symbol).delete_all
      OptionsTrader::PriceHistory.where(symbol: underlying_symbol).delete_all
    end

    it 'fetches the most recent option data within the time window' do
      result = described_class.fetch_with_locf(
        expiration_date: expiration_date,
        underlying_symbol: underlying_symbol,
        end_time: end_time,
        window: 5,
        source: 'polygon'
      )

      # Should get 3 records (2 CALLs + 1 PUT), excluding the zero mark and old data
      expect(result.count).to eq(3)
    end

    it 'uses LOCF to pick the most recent record per symbol' do
      result = described_class.fetch_with_locf(
        expiration_date: expiration_date,
        underlying_symbol: underlying_symbol,
        end_time: end_time,
        window: 5,
        source: 'polygon'
      )

      # Find the C06410 record
      c6410_record = result.find { |r| r['symbol'] == 'SPXW250810C06410' }
      expect(c6410_record).to be_present

      # Should be the most recent mark price (127.50, not 125.00)
      expect(c6410_record['mark'].to_f).to eq(127.50)
    end

    it 'filters out records with mark <= 0' do
      result = described_class.fetch_with_locf(
        expiration_date: expiration_date,
        underlying_symbol: underlying_symbol,
        end_time: end_time,
        window: 5,
        source: 'polygon'
      )

      # C06420 with mark=0 should not be included
      c6420_record = result.find { |r| r['symbol'] == 'SPXW250810C06420' }
      expect(c6420_record).to be_nil
    end

    it 'joins with the most recent underlying price from price_history' do
      result = described_class.fetch_with_locf(
        expiration_date: expiration_date,
        underlying_symbol: underlying_symbol,
        end_time: end_time,
        window: 5,
        source: 'polygon'
      )

      # All records should have the underlying_price from the LOCF join
      result.each do |record|
        expect(record['underlying_price']).to be_present
        # The underlying price should be from price_history (close values)
        expect([6522.50, 6532.15, 6538.92]).to include(record['underlying_price'].to_f)
      end
    end

    it 'orders results by strike price' do
      result = described_class.fetch_with_locf(
        expiration_date: expiration_date,
        underlying_symbol: underlying_symbol,
        end_time: end_time,
        window: 5,
        source: 'polygon'
      )

      strikes = result.map { |r| r['strike'].to_f }
      expect(strikes).to eq(strikes.sort)
    end

    it 'respects the time window parameter' do
      # Use a 2-minute window which should exclude most records except the last one
      result = described_class.fetch_with_locf(
        expiration_date: expiration_date,
        underlying_symbol: underlying_symbol,
        end_time: end_time,
        window: 2,
        source: 'polygon'
      )

      # Only the record at 10:04:00 should be included (within 2 minutes of 10:05, after 10:03)
      # The query uses > (not >=) for window_start, so 10:03:00 is excluded
      expect(result.count).to eq(1)
      expect(result.first['symbol']).to eq('SPXW250810C06410')
    end

    it 'filters by source' do
      # Create a record with different source
      described_class.create!(
        symbol: 'SPXW250810C06430',
        root_symbol: 'SPXW',
        underlying_symbol: underlying_symbol,
        expiration_date: expiration_date,
        strike: 6430.00,
        contract_type: 'CALL',
        valid_time: Time.parse('2025-08-01 10:02:00 UTC'),
        transaction_time: Time.parse('2025-08-01 10:02:00 UTC'),
        mark: 115.00, bid: 113.50, ask: 116.50,
        underlying_price: 6538.92,
        source: 'tradier'
      )

      result = described_class.fetch_with_locf(
        expiration_date: expiration_date,
        underlying_symbol: underlying_symbol,
        end_time: end_time,
        window: 5,
        source: 'polygon'
      )

      # Should not include the tradier record
      tradier_record = result.find { |r| r['symbol'] == 'SPXW250810C06430' }
      expect(tradier_record).to be_nil
    end
  end
end
