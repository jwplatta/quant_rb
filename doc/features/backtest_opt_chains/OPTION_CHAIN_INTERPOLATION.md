# Option Chain Interpolation

## Implementation

1. Update the polgyon client to return and object chain data object
  - Need a method that takes a symbol, datetime range, and step size (min, 5 min, week, etc.)
```ruby
def get_aggs(symbol:, start_datetime:, end_datetime: nil, agg_size: 'min', local_dir: "./")
end
```
  - Will need to parse `O:SPXW250102C04500000,2,1397.95,1397.95,1397.95,1397.95,1735835100000000000,1`
  - The downloaded CSV has all the agg data for all tickers for a single day. So you will have to search through it to get the ticker you want and then make sure that it's sorted correctly.
  - The timestamps are unix epoch timestamps in nanoseconds:
```ruby
# convert nanoseconds -> Time
ts_ns = 1_735_835_100_000_000_000
secs = ts_ns / 1_000_000_000
nsecs = ts_ns % 1_000_000_000
Time.at(secs, nsecs, :nsec)     # => 2025-01-02 16:25:00 UTC

# or simpler
Time.at(ts_ns / 1_000_000_000.0)
```
2.

## Algorithm

For each 15-min sample (current time t):

1. Get current_spot and ATM_straddle_price → current_1σ_move
  - Get the price of the ATM PUT and the ATM CALL and add them together

2. Calculate target strikes for current sample:
   strike_1σ_call = current_spot + current_1σ_move
   strike_2σ_call = current_spot + (2 × current_1σ_move)
   strike_3σ_call = current_spot + (3 × current_1σ_move)

   strike_1σ_put = current_spot - current_1σ_move
   strike_2σ_put = current_spot - (2 × current_1σ_move)
   strike_3σ_put = current_spot - (3 × current_1σ_move)

   # Find actual strikes closest to these
   key_strikes = [strike_1σ_call, strike_2σ_call, strike_3σ_call,
                  strike_1σ_put, strike_2σ_put, strike_3σ_put]

3. For THESE SAME STRIKES, calculate deltas for last 3 samples:

   For strike in key_strikes:
     deltas = []

     for sample_time in [t, t-15min, t-30min]:
       delta = (price[strike, sample_time] - price[strike, sample_time-15min]) / Δspot
       deltas.append(delta)

     averaged_delta[strike] = mean(deltas)

4. Now you have averaged deltas at your key strikes:
   averaged_delta = {
     6700: 0.18,  # ~1σ call
     6800: 0.03,  # ~2σ call
     6900: 0.01,  # ~3σ call
     6500: -0.20, # ~1σ put
     ...
   }

5. Interpolate for all strikes in option chain:
   For each strike in chain:
     delta = interpolate(averaged_delta, strike)

## Dependencies

- We need write an interpolator module
```ruby
module DeltaInterpolator
  def self.interpolate(strike_deltas, target_strike)
    # strike_deltas is a hash: { strike => delta }
    sorted_strikes = strike_deltas.keys.sort

    # Handle boundaries
    return strike_deltas[sorted_strikes.first] if target_strike <= sorted_strikes.first
    return strike_deltas[sorted_strikes.last] if target_strike >= sorted_strikes.last

    # Find bracketing strikes
    upper_idx = sorted_strikes.bindex { |s| s > target_strike }
    lower_strike = sorted_strikes[upper_idx - 1]
    upper_strike = sorted_strikes[upper_idx]

    # Linear interpolation
    lower_delta = strike_deltas[lower_strike]
    upper_delta = strike_deltas[upper_strike]

    weight = (target_strike - lower_strike).to_f / (upper_strike - lower_strike)
    lower_delta + weight * (upper_delta - lower_delta)
  end
end

# Usage
strike_deltas = { 6500 => -0.20, 6700 => 0.18, 6800 => 0.03 }
DeltaInterpolator.interpolate(strike_deltas, 6750)  # => ~0.10
```

- Use the `Polygon::Client.get_aggs` method in lib/options_trader/data_providers/polygon/client.rb

## Design

