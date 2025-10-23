# determine time intervals
require 'time'
require_relative '../../lib/options_trader'
require 'active_support/time'
require 'pry'

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

@delta_enricher = OptionsTrader::Services::DeltaEnricher.new(predictor: greek_predictor)

# Market full-closure dates (observed) and early closures for 2023-2025
FULL_CLOSURES = [
  # New Year's Day (observed)
  Date.new(2023, 1, 2), Date.new(2024, 1, 1), Date.new(2025, 1, 1),
  # Martin Luther King Jr. Day
  Date.new(2023, 1, 16), Date.new(2024, 1, 15), Date.new(2025, 1, 20),
  # Presidents' Day (Washington's Birthday)
  Date.new(2023, 2, 20), Date.new(2024, 2, 19), Date.new(2025, 2, 17),
  # Good Friday
  Date.new(2023, 4, 7), Date.new(2024, 3, 29), Date.new(2025, 4, 18),
  # Memorial Day
  Date.new(2023, 5, 29), Date.new(2024, 5, 27), Date.new(2025, 5, 26),
  # Juneteenth
  Date.new(2023, 6, 19), Date.new(2024, 6, 19), Date.new(2025, 6, 19),
  # Independence Day
  Date.new(2023, 7, 4), Date.new(2024, 7, 4), Date.new(2025, 7, 4),
  # Labor Day
  Date.new(2023, 9, 4), Date.new(2024, 9, 2), Date.new(2025, 9, 1),
  # Thanksgiving Day
  Date.new(2023, 11, 23), Date.new(2024, 11, 28), Date.new(2025, 11, 27),
  # Christmas Day
  Date.new(2023, 12, 25), Date.new(2024, 12, 25), Date.new(2025, 12, 25)
].freeze

EARLY_CLOSURES = [
  # Day before Independence Day (early close)
  Date.new(2023, 7, 3), Date.new(2024, 7, 3), Date.new(2025, 7, 3),
  # Day after Thanksgiving (Black Friday, early close)
  Date.new(2023, 11, 24), Date.new(2024, 11, 29), Date.new(2025, 11, 28),
  # Christmas Eve (early close)
  Date.new(2023, 12, 24), Date.new(2024, 12, 24), Date.new(2025, 12, 24)
].freeze

CPI_RELEASES = [
  # 2023
  Date.new(2023, 1, 12),   # December 2022 CPI
  Date.new(2023, 2, 14),   # January 2023 CPI
  Date.new(2023, 3, 14),   # February 2023 CPI
  Date.new(2023, 4, 12),   # March 2023 CPI
  Date.new(2023, 5, 10),   # April 2023 CPI
  Date.new(2023, 6, 13),   # May 2023 CPI
  Date.new(2023, 7, 12),   # June 2023 CPI
  Date.new(2023, 8, 10),   # July 2023 CPI
  Date.new(2023, 9, 13),   # August 2023 CPI
  Date.new(2023, 10, 12),  # September 2023 CPI
  Date.new(2023, 11, 14),  # October 2023 CPI
  Date.new(2023, 12, 12),  # November 2023 CPI

  # 2024
  Date.new(2024, 1, 11),   # December 2023 CPI
  Date.new(2024, 2, 13),   # January 2024 CPI
  Date.new(2024, 3, 12),   # February 2024 CPI
  Date.new(2024, 4, 10),   # March 2024 CPI
  Date.new(2024, 5, 15),   # April 2024 CPI
  Date.new(2024, 6, 12),   # May 2024 CPI
  Date.new(2024, 7, 11),   # June 2024 CPI
  Date.new(2024, 8, 14),   # July 2024 CPI
  Date.new(2024, 9, 11),   # August 2024 CPI
  Date.new(2024, 10, 10),  # September 2024 CPI
  Date.new(2024, 11, 13),  # October 2024 CPI
  Date.new(2024, 12, 11),  # November 2024 CPI

  # 2025
  Date.new(2025, 1, 15),   # December 2024 CPI
  Date.new(2025, 2, 12),   # January 2025 CPI
  Date.new(2025, 3, 12),   # February 2025 CPI
  Date.new(2025, 4, 10),   # March 2025 CPI
  Date.new(2025, 5, 13),   # April 2025 CPI
  Date.new(2025, 6, 11),   # May 2025 CPI
  Date.new(2025, 7, 10),   # June 2025 CPI
  Date.new(2025, 8, 13),   # July 2025 CPI
  Date.new(2025, 9, 11),   # August 2025 CPI
  Date.new(2025, 10, 24),  # September 2025 CPI (rescheduled due to government shutdown)
  Date.new(2025, 11, 13),  # October 2025 CPI (estimated)
  Date.new(2025, 12, 11)   # November 2025 CPI (estimated)
].freeze

FOMC_MEETINGS = [
  # 2023 (second day of each meeting listed)
  Date.new(2023, 2, 1),    # Jan 31 - Feb 1
  Date.new(2023, 3, 22),   # Mar 21-22 * (with SEP)
  Date.new(2023, 5, 3),    # May 2-3
  Date.new(2023, 6, 14),   # Jun 13-14 * (with SEP)
  Date.new(2023, 7, 26),   # Jul 25-26
  Date.new(2023, 9, 20),   # Sep 19-20 * (with SEP)
  Date.new(2023, 11, 1),   # Oct 31 - Nov 1
  Date.new(2023, 12, 13),  # Dec 12-13 * (with SEP)

  # 2024 (second day of each meeting listed)
  Date.new(2024, 1, 31),   # Jan 30-31
  Date.new(2024, 3, 20),   # Mar 19-20 * (with SEP)
  Date.new(2024, 5, 1),    # Apr 30 - May 1
  Date.new(2024, 6, 12),   # Jun 11-12 * (with SEP)
  Date.new(2024, 7, 31),   # Jul 30-31
  Date.new(2024, 9, 18),   # Sep 17-18 * (with SEP)
  Date.new(2024, 11, 7),   # Nov 6-7
  Date.new(2024, 12, 18),  # Dec 17-18 * (with SEP)

  # 2025 (second day of each meeting listed)
  Date.new(2025, 1, 29),   # Jan 28-29
  Date.new(2025, 3, 19),   # Mar 18-19 * (with SEP)
  Date.new(2025, 5, 7),    # May 6-7
  Date.new(2025, 6, 18),   # Jun 17-18 * (with SEP)
  Date.new(2025, 7, 30),   # Jul 29-30
  Date.new(2025, 9, 17),   # Sep 16-17 * (with SEP)
  Date.new(2025, 10, 29),  # Oct 28-29 (estimated)
  Date.new(2025, 12, 10)   # Dec 9-10 * (with SEP) (estimated)
].freeze

UNEMPLOYMENT_RATE_RELEASES = [
  # 2023
  Date.new(2023, 1, 6),    # December 2022 data
  Date.new(2023, 2, 3),    # January 2023 data
  Date.new(2023, 3, 10),   # February 2023 data
  Date.new(2023, 4, 7),    # March 2023 data
  Date.new(2023, 5, 5),    # April 2023 data
  Date.new(2023, 6, 2),    # May 2023 data
  Date.new(2023, 7, 7),    # June 2023 data
  Date.new(2023, 8, 4),    # July 2023 data
  Date.new(2023, 9, 1),    # August 2023 data
  Date.new(2023, 10, 6),   # September 2023 data
  Date.new(2023, 11, 3),   # October 2023 data
  Date.new(2023, 12, 8),   # November 2023 data

  # 2024
  Date.new(2024, 1, 5),    # December 2023 data
  Date.new(2024, 2, 2),    # January 2024 data
  Date.new(2024, 3, 8),    # February 2024 data
  Date.new(2024, 4, 5),    # March 2024 data
  Date.new(2024, 5, 3),    # April 2024 data
  Date.new(2024, 6, 7),    # May 2024 data
  Date.new(2024, 7, 5),    # June 2024 data
  Date.new(2024, 8, 2),    # July 2024 data
  Date.new(2024, 9, 6),    # August 2024 data
  Date.new(2024, 10, 4),   # September 2024 data
  Date.new(2024, 11, 1),   # October 2024 data
  Date.new(2024, 12, 6),   # November 2024 data

  # 2025
  Date.new(2025, 1, 10),   # December 2024 data
  Date.new(2025, 2, 7),    # January 2025 data
  Date.new(2025, 3, 7),    # February 2025 data
  Date.new(2025, 4, 4),    # March 2025 data
  Date.new(2025, 5, 2),    # April 2025 data
  Date.new(2025, 6, 6),    # May 2025 data
  Date.new(2025, 7, 3),    # June 2025 data
  Date.new(2025, 8, 1),    # July 2025 data
  Date.new(2025, 9, 5),    # August 2025 data
  Date.new(2025, 10, 3),   # September 2025 data
  Date.new(2025, 11, 7),   # October 2025 data
  Date.new(2025, 12, 5)    # November 2025 data
].freeze

def is_holiday_or_early_close?(date)
  FULL_CLOSURES.include?(date) || EARLY_CLOSURES.include?(date)
end

def is_cpi_release_date?(date)
  CPI_RELEASES.include?(date)
end

def is_fomc_meeting_date?(date)
  FOMC_MEETINGS.include?(date)
end

def is_unemployment_release_date?(date)
  UNEMPLOYMENT_RATE_RELEASES.include?(date)
end

def is_weekend?(date)
  date.saturday? || date.sunday?
end

def next_day_expiration_date(from_date)
  tomorrow = from_date.next_day

  if is_weekend?(tomorrow)
    next_day_expiration_date(tomorrow)
  elsif is_holiday_or_early_close?(tomorrow)
    next_day_expiration_date(tomorrow)
  else
    tomorrow
  end
end

def find_straddle_price(option_chain)
  call_atm = option_chain.call_opts.min_by { |opt| (opt.strike - option_chain.underlying_price).abs }
  put_atm = option_chain.put_opts.min_by { |opt| (opt.strike - option_chain.underlying_price).abs }

  return nil if call_atm.nil? || put_atm.nil?

  call_atm.mark + put_atm.mark
end

def find_nearest_option(option_chain, target_strike, contract_type)
  if contract_type == 'PUT'
    option_chain.put_opts.min_by { |opt| (opt.strike - target_strike).abs }
  else
    option_chain.call_opts.min_by { |opt| (opt.strike - target_strike).abs }
  end
end

def enrich_option_chain_with_deltas(option_chain)
  begin
    @delta_enricher.enrich(option_chain)
  rescue OptionsTrader::Services::DeltaEnricher::Error => e
    puts "ERROR: Failed to enrich option chain: #{e.message}"
    exit 1
  end
end

UNDERLYING_SYMBOL = '$SPX'
# START_DATE = Date.new(2025, 1, 27)
START_DATE = Date.new(2025, 2, 19)
END_DATE = Date.new(2025, 10, 01)
curr_date = START_DATE
trading_day_cnt = 0

while true
  puts "Date: #{curr_date}"

  if is_holiday_or_early_close?(curr_date)
    puts "  Skipping market holiday or early close"
  elsif is_cpi_release_date?(curr_date)
    puts "  Skipping CPI release date"
  elsif is_fomc_meeting_date?(curr_date)
    puts "  Skipping FOMC meeting date"
  elsif is_unemployment_release_date?(curr_date)
    puts "  Skipping Unemployment Rate release date"
  elsif is_weekend?(curr_date)
    puts "  Skipping weekend"
  else
    central_259 = central_time_zone.local(curr_date.year, curr_date.month, curr_date.day, 14, 59, 0)
    valid_time = central_259.utc
    trading_day_cnt += 1

    puts "  Valid Time (UTC): #{valid_time.iso8601}"

    snapshot_service = OptionsTrader::Services::HistoricalSnapshot.new(
      valid_time: valid_time
    )

    option_chain = snapshot_service.get_option_chain(
      UNDERLYING_SYMBOL,
      expiration_date: next_day_expiration_date(curr_date).to_s,
      window: 5,
      features: {
        vix9d: '$VIX9D',
        vvix: '$VVIX'
      }
    )

    option_chain = enrich_option_chain_with_deltas(option_chain)

    straddle_price = find_straddle_price(option_chain)
    puts "  ATM Straddle Price: $#{straddle_price}" if straddle_price

    sig_up = option_chain.underlying_price + straddle_price * 2
    sig_down = option_chain.underlying_price - straddle_price * 2

    short_call = find_nearest_option(option_chain, sig_up, 'CALL')
    long_call = find_nearest_option(option_chain, sig_up + 20, 'CALL')
    short_put = find_nearest_option(option_chain, sig_down, 'PUT')
    long_put = find_nearest_option(option_chain, sig_down - 20, 'PUT')

    call_vertical_mark = short_call.mark - long_call.mark
    put_vertical_mark = short_put.mark - long_put.mark

    total_credit = call_vertical_mark + put_vertical_mark
    puts "  Total Iron Condor Credit: $#{total_credit.round(2)}"

    # puts "  Underlying Price: $#{option_chain.underlying_price}"
    # puts "  Call Options: #{option_chain.call_opts.size}"
    # puts "  Put Options: #{option_chain.put_opts.size}"
    puts "--------------------------------------------------------"
  end

  curr_date += 1
  break if curr_date >= END_DATE
end

puts "Total trading days processed: #{trading_day_cnt}"