# frozen_string_literal: true

require_relative "../lib/quant_rb"
require 'pry'

START_DATE = Date.iso8601("2026-03-09")
END_DATE = Date.iso8601("2026-03-09")
RESOLUTION = "5min".to_sym
MARKET_TIMEZONE = "America/Chicago"
MAX_OBSERVATIONS = 100

class InspectSpxwSampledChainTimesExample < QuantRb::Strategy
  class << self
    attr_accessor :instance
  end

  attr_reader :observations

  def self.build_for_engine(**kwargs)
    self.instance = super
  end

  def initialize
    set_start_date(START_DATE.year, START_DATE.month, START_DATE.day)
    set_end_date(END_DATE.year, END_DATE.month, END_DATE.day)
    set_cash(100_000)
    set_market_timezone(MARKET_TIMEZONE)

    @spx = add_index("SPX", resolution: RESOLUTION)
    @spxw = add_option_chain("SPX", "SPXW", resolution: RESOLUTION, dataset: "schwab_samples")
    @observations = []
  end

  def on_data(slice)
    return if @observations.size >= MAX_OBSERVATIONS

    chains = slice.option_chains[@spxw] || {}

    return if chains.empty?

    expiries = chains.keys.sort
    reference_expiry = expiries.find { |expiry| expiry >= market_date } || expiries.first
    reference_chain = reference_expiry && chains[reference_expiry]
    sampled_option = reference_chain&.all_options&.first

    @observations << {
      time: time,
      market_date: market_date,
      utc_time: time.getutc,
      utc_offset: time.utc_offset,
      visible_expiries: expiries.first(6),
      reference_expiry: reference_expiry,
      reference_chain_sampled_at: reference_chain&.sampled_at,
      reference_option_timestamp: sampled_option&.timestamp,
      reference_option_dte: sampled_option&.days_to_expiration
    }
  end
end

QuantRb.configure do |config|
  config.data_sources_config_path = ENV.fetch("QUANT_RB_DATA_SOURCES_CONFIG_PATH", QuantRb.config.data_sources_config_path)
  config.log_level = ENV.fetch("QUANT_RB_LOG_LEVEL", "info")
  config.market_timezone = MARKET_TIMEZONE
end

result = QuantRb::BacktestEngine.run(InspectSpxwSampledChainTimesExample, progress: false)
strategy = InspectSpxwSampledChainTimesExample.instance

puts "SPXW sampled chain inspection"
puts "period=#{START_DATE}..#{END_DATE} resolution=#{RESOLUTION} market_timezone=#{MARKET_TIMEZONE}"
puts "data_sources_config=#{QuantRb.config.data_sources_config_path}"
puts

if strategy.observations.empty?
  puts "No option-chain observations were captured."
else
  strategy.observations.each_with_index do |observation, index|
    puts "Observation #{index + 1}"
    puts "  time=#{observation[:time]}"
    puts "  market_date=#{observation[:market_date]}"
    puts "  utc_time=#{observation[:utc_time]}"
    puts "  utc_offset=#{observation[:utc_offset]}"
    puts "  visible_expiries=#{observation[:visible_expiries].join(', ')}"
    puts "  reference_expiry=#{observation[:reference_expiry]}"
    puts "  chain_sampled_at=#{observation[:reference_chain_sampled_at]}"
    puts "  option_timestamp=#{observation[:reference_option_timestamp]}"
    puts "  option_dte=#{observation[:reference_option_dte]}"
    puts
  end
end

binding.pry

puts result.summary
