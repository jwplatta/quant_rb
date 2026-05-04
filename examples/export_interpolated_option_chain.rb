# frozen_string_literal: true

require "date"
require_relative "../lib/quant_rb"

provider = ENV.fetch("PROVIDER", "massive")
underlying_provider = ENV.fetch("UNDERLYING_PROVIDER", 'ibkr-paper')
underlying = ENV.fetch("UNDERLYING", "SPX")
option_root = ENV.fetch("OPTION_ROOT", "SPXW")
resolution = ENV.fetch("RESOLUTION", "minute").to_sym
timestamp = Time.parse(ENV.fetch("TIMESTAMP", "2024-10-15T15:30:00Z")).utc
expiry = Date.iso8601(ENV.fetch("EXPIRY", "2024-10-16"))
pricing_model = ENV.fetch("PRICING_MODEL", "black_scholes").to_sym
validation = ENV.fetch("VALIDATION", "repair").to_sym
strike_step = ENV.fetch("STRIKE_STEP", "5.0").to_f
range_ratio = ENV.fetch("RANGE_RATIO", "0.30").to_f
output_dir = ENV.fetch("OUTPUT_DIR", Dir.pwd)

config = QuantRb::Data::OptionChainConfig.new(
  underlying: underlying,
  option_root: option_root,
  resolution: resolution,
  provider: provider,
  chain_mode: :sampled_interpolated,
  pricing_model: pricing_model,
  iv_map: nil,
  validation: validation,
  strike_grid: { step: strike_step, range_ratio: range_ratio },
  raw_options: { underlying_provider: underlying_provider }
)

source = QuantRb::Data::OptionChainSource.build(
  config: config,
  start_date: timestamp.to_date,
  end_date: timestamp.to_date
)

chain = source.chains_at(timestamp, expiry_filter: expiry).fetch(expiry)
path = chain.to_csv(dir: output_dir)

puts "provider=#{provider}"
puts "underlying=#{underlying}"
puts "underlying_provider=#{underlying_provider}"
puts "option_root=#{option_root}"
puts "timestamp=#{timestamp.utc.iso8601}"
puts "expiry=#{expiry}"
puts "range_ratio=#{range_ratio}"
puts "calls=#{chain.call_opts.size}"
puts "puts=#{chain.put_opts.size}"
puts "csv=#{path}"
