# frozen_string_literal: true

require 'spec_helper'
require 'tzinfo'
require_relative '../../spx_1dte/bot_config'

RSpec.describe BotConfig do
  let(:config_path) { File.expand_path('../../config/spx_1dte.yml', __dir__) }
  let(:config) { described_class.new(config_path) }

  def expect_time_in_zone(time, expected_label, timezone: 'America/Chicago')
    expect(time).to be_a(Time)
    expect(time.strftime('%I:%M %p')).to eq(expected_label)

    tz = TZInfo::Timezone.get(timezone)
    period = tz.period_for_local(time)
    expect(period.abbreviation.to_s).to eq(time.zone)
  end

  describe '#initialize' do
    it 'loads trade attributes from the YAML config' do
      yaml_config = YAML.load_file(config_path)
      trade_config = yaml_config['trade'] || {}

      trade_config.each do |key, expected_value|
        expect(config.public_send(key)).to eq(expected_value)
      end
    end
  end

  describe '#initialize' do
    it 'raises when the config file is missing' do
      expect { described_class.new('/tmp/missing.yml') }
        .to raise_error(RuntimeError, /Config file not found/)
    end
  end

  describe 'date lookups' do
    it 'marks high risk dates as unsafe for trading' do
      date = Date.new(2025, 12, 5)

      expect(config.high_risk_date?(date)).to be(true)
      expect(config.trading_allowed?(date)).to be(false)
      expect(config.low_risk_date?(date)).to be(false)
    end

    it 'detects holidays' do
      holiday = Date.new(2025, 11, 27)

      expect(config.holiday?(holiday)).to be(true)
    end

    it 'detects early close dates' do
      early_close = Date.new(2025, 11, 28)

      expect(config.early_close_date?(early_close)).to be(true)
    end
  end

  describe 'time windows' do
    it 'returns default windows on normal days' do
      date = Date.new(2025, 12, 5) # not an early close day

      expect(config.enter_trade_window(date)).to eq(
        start_time: '02:55 PM',
        end_time: '03:15 PM',
        timezone: 'America/Chicago'
      )

      expect(config.monitoring_window(date)).to eq(
        start_time: '08:25 AM',
        end_time: '03:15 PM',
        exit_by_time: '12:00 PM',
        timezone: 'America/Chicago'
      )
    end

    it 'returns early close windows on early close days' do
      early_close = Date.new(2025, 11, 28)

      expect(config.enter_trade_window(early_close)).to eq(
        start_time: '11:55 AM',
        end_time: '12:15 PM',
        timezone: 'America/Chicago'
      )

      expect(config.monitoring_window(early_close)).to eq(
        start_time: '08:25 AM',
        end_time: '12:15 PM',
        exit_by_time: '11:00 AM',
        timezone: 'America/Chicago'
      )
    end
  end

  describe 'window helper times' do
    let(:normal_date) { Date.new(2025, 12, 5) }
    let(:early_close_date) { Date.new(2025, 11, 28) }

    it 'parses monitoring and trade windows into timezone-aware times on regular days' do
      expect_time_in_zone(config.monitoring_start_time(normal_date), '08:25 AM')
      expect_time_in_zone(config.monitoring_end_time(normal_date), '03:15 PM')
      expect_time_in_zone(config.enter_trade_window_start_time(normal_date), '02:55 PM')
      expect_time_in_zone(config.enter_trade_window_end_time(normal_date), '03:15 PM')
    end

    it 'honors the early close schedule for monitoring and trade times' do
      expect_time_in_zone(config.monitoring_start_time(early_close_date), '08:25 AM')
      expect_time_in_zone(config.monitoring_end_time(early_close_date), '12:15 PM')
      expect_time_in_zone(config.enter_trade_window_start_time(early_close_date), '11:55 AM')
      expect_time_in_zone(config.enter_trade_window_end_time(early_close_date), '12:15 PM')
    end
  end
end
