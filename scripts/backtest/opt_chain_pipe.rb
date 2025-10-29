# determine time intervals
require 'time'
require_relative '../../lib/options_trader'
require 'active_support/time'
require 'pry'
require 'csv'

central_time_zone = ActiveSupport::TimeZone['Central Time (US & Canada)']
UNDERLYING_SYMBOL = '$SPX'
ROOT_SYMBOL = 'SPXW'

greek_predictor = OptionsTrader::Predictors::GreekForge.new(
  host: ENV.fetch('GREEK_FORGE_HOST', 'localhost'),
  port: ENV.fetch('GREEK_FORGE_PORT', 8000).to_i,
  scheme: ENV.fetch('GREEK_FORGE_SCHEME', 'http')
)

begin
  health_response = greek_predictor.health
  puts "Greek Forge service is healthy: #{health_response}"
rescue OptionsTrader::Predictors::GreekForge::ConnectionError => e
  puts "ERROR: Cannot connect to Greek Forge service: #{e.message}"
  puts "Please ensure the Greek Forge service is running on #{greek_predictor.scheme}://#{greek_predictor.host}:#{greek_predictor.port}"
  exit 1
end

# NOTE: testing the fetch_with_locf method directly
exp_date = Date.parse('2025-08-11')

# WHERE expiration_date = '2025-08-11'
# AND valid_time > '2025-08-08 20:25:00 UTC'
# AND valid_time <= '2025-08-08 20:30:00 UTC'

# def self.fetch_with_locf(expiration_date:, underlying_symbol:, end_time:, window: 5, source: 'polygon')
# records = OptionsTrader::OptionChainHistory.fetch_with_locf(
#   expiration_date: exp_date,
#   underlying_symbol: '$SPX',
#   end_time: Time.parse('2025-08-08 20:30:00'),
#   window: 20,
#   source: 'polygon'
# )
delta_enricher = OptionsTrader::Services::DeltaEnricher.new(predictor: greek_predictor)

valid_time = ActiveSupport::TimeZone['UTC'].parse('2025-08-08 20:30:00')
snapshot_service = OptionsTrader::Services::HistoricalSnapshot.new(
  valid_time: valid_time,
)

option_chain = snapshot_service.get_option_chain(
  UNDERLYING_SYMBOL,
  expiration_date: exp_date,
  window: 20
)

features = snapshot_service.get_quotes(
  ['$VVIX', '$VIX9D'],
  window: 120
).map { |q| [q.readable_symbol, q.close] }.to_h

opt_chain = OptionsTrader::SyntheticData::OptionChainPipeline.new(option_chain, greek_predictor: greek_predictor)
    .with_features(features)
    .enforce_monotonicity(method: 'remove')
    .complete_strikes(min_strike: 5800, max_strike: 8000)
    .interpolate_prices
    .build
    # .enrich_deltas

rows = {}
opt_chain.call_opts.each do |opt|
  rows[opt.strike] ||= {}
  rows[opt.strike][:call] = {
    mark: opt.mark,
    intrinsic: opt.intrinsic,
    extrinsic: opt.extrinsic,
    high: opt.high,
    low: opt.low,
    close: opt.close,
    open: opt.open
  }
end

opt_chain.put_opts.each do |opt|
  rows[opt.strike] ||= {}
  rows[opt.strike][:put] = {
    mark: opt.mark,
    intrinsic: opt.intrinsic,
    extrinsic: opt.extrinsic,
    high: opt.high,
    low: opt.low,
    close: opt.close,
    open: opt.open
  }
end


CSV.open('test_opt_chain_4.csv', 'w') do |csv|
  csv << [
    'call_mark', 'call_intrinsic', 'call_extrinsic', 'call_high', 'call_low', 'call_close', 'call_open',
    'strike',
    'put_mark', 'put_intrinsic', 'put_extrinsic', 'put_high', 'put_low', 'put_close', 'put_open'
  ]

  rows.keys.sort.each do |strike|
    call_data = rows[strike][:call] || {}
    put_data = rows[strike][:put] || {}

    csv << [
      call_data[:mark],
      call_data[:intrinsic],
      call_data[:extrinsic],
      call_data[:high],
      call_data[:low],
      call_data[:close],
      call_data[:open],
      strike,
      put_data[:mark],
      put_data[:intrinsic],
      put_data[:extrinsic],
      put_data[:high],
      put_data[:low],
      put_data[:close],
      put_data[:open]
    ]
  end
end

binding.pry