# frozen_string_literal: true

require 'spec_helper'

RSpec.describe OptionsTrader::PriceHistory, type: :model do
  describe '.fetch_with_locf' do
    let(:symbol) { 'SPY' }
    let(:end_time) { Time.parse('2025-01-15 10:00:00') }

    before do
      described_class.where(symbol: symbol).delete_all

      described_class.create!(
        symbol: symbol,
        open: 100.0,
        close: 101.0,
        high: 102.0,
        low: 99.0,
        volume: 1000,
        interval: '5min',
        valid_time: Time.parse('2025-01-15 09:55:00')
      )

      described_class.create!(
        symbol: symbol,
        open: 101.0,
        close: 102.0,
        high: 103.0,
        low: 100.0,
        volume: 1500,
        interval: '5min',
        valid_time: Time.parse('2025-01-15 09:58:00')
      )
    end

    after do
      described_class.where(symbol: symbol).delete_all
    end

    it 'returns the most recent record within the window' do
      result = described_class.fetch_with_locf(
        symbol: symbol,
        end_time: end_time,
        window: 5,
        interval: '5min'
      )

      expect(result).not_to be_nil
      expect(result.close).to eq(102.0)
      expect(result.valid_time).to eq(Time.parse('2025-01-15 09:58:00'))
    end

    it 'returns nil when no records exist within the window' do
      result = described_class.fetch_with_locf(
        symbol: symbol,
        end_time: Time.parse('2025-01-15 09:00:00'),
        window: 5,
        interval: '5min'
      )

      expect(result).to be_nil
    end
  end
end
