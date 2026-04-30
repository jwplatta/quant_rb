# Synthetic Chain Pipeline Design

## Overview

The `SyntheticData` module provides a pipeline for transforming raw historical option chains into complete, arbitrage-free synthetic chains suitable for backtesting. Transformations are applied sequentially with explicit dependencies between stages.

## Refactor Stpes

### Step 1: OptionsTrader::SyntheticData::Transform::MonotonicityEnforcer

Updating the monotonicity logic we need to apply the monotonicity to original option_chain, but we need to do it carefully:
1. If we find cases there the violation is very close in price to its neighbors, then just just copy the price of one of the neighbors.
2. If we find a violation and the spread between its neighbors is wide and the violation is way out of line, then we should:
  - first look at the open_price, high_price, low_price (other attrs on the record) and see if any of these prices do not violate monotonicity.
  - If not, then we should try averaging the open, close, high, and low prices and see if that average does not violate the monotonicity.
  - If not, then as a last resort we should find the midpoint between the neighbors and use that. Of course this process might introduce new monotonicity violations.
So we need to repeat the monotonicity check on the updated options and see if we created any new violations.

We need to refactor the monotonicity enforcer a bit. when enforcing zmonotonicity:
- First we need to separate the OTM and ITM options.
- Then we need to extract the extrinsic from intrinsic value for OTM options.
- We can infer the extrinsic value by calculating the intrinsic value and then subtracting it from the options

### Step 2: OptionsTrader::SyntheticData::Transform::StrikeAdder

Generates synthetic options for missing strikes in the option chain. Acceptance criteria include
- generate the array of strikes by using the min offset and max offset from the current underlying price.

```ruby
# Strike generation defaults
DEFAULT_MIN_OFFSET = -3000
DEFAULT_MAX_OFFSET = 1000
DEFAULT_INNER_OFFSET = 225
DEFAULT_INNER_STEP = 5
DEFAULT_OUTER_STEP = 25

def generate_target_strikes(
  underlying_price,
  min_strike: nil,
  max_strike: nil,
  min_offset: DEFAULT_MIN_OFFSET,
  max_offset: DEFAULT_MAX_OFFSET,
  inner_offset: DEFAULT_INNER_OFFSET,
  inner_step: DEFAULT_INNER_STEP,
  outer_step: DEFAULT_OUTER_STEP
)
  # Round underlying to nearest outer_step
  base_strike = (underlying_price / outer_step.to_f).round * outer_step

  unless min_strike.present? && max_strike.present?
    min_strike = base_strike + min_offset
    max_strike = base_strike + max_offset
  end

  inner_min_strike = base_strike - inner_offset
  inner_max_strike = base_strike + inner_offset

  # Align inner_max_strike to outer_step boundary
  while inner_max_strike % outer_step != 0
    inner_max_strike += inner_step
  end

  strikes = []
  current_strike = min_strike

  while current_strike <= max_strike
    strikes << current_strike
    step = (current_strike >= inner_min_strike && current_strike < inner_max_strike) ? inner_step : outer_step
    current_strike += step
  end

  strikes.sort
end

# Merges existing options with synthetic options for missing strikes.
# Synthetic options carry the same feature values as real options.
def build_complete_option_arrays(
  underlying_symbol, calls, puts,
  target_strikes, underlying_price, dte, expiration_date, feature_values = nil
)
  min_strike = target_strikes.min
  max_strike = target_strikes.max
  calls_by_strike = calls.index_by(&:strike)
  puts_by_strike = puts.index_by(&:strike)

  complete_calls = []
  complete_puts = []

  target_strikes.each do |strike|
    if calls_by_strike[strike]
      complete_calls << calls_by_strike[strike]
    else
      complete_calls << create_synthetic_option(
        underlying_symbol: underlying_symbol,
        strike: strike,
        contract_type: 'CALL',
        underlying_price: underlying_price,
        days_to_expiration: dte,
        expiration_date: expiration_date,
        mark: (strike == max_strike ? DEFAULT_MIN_MARK : nil),
        feature_values: feature_values
      )
    end

    if puts_by_strike[strike]
      complete_puts << puts_by_strike[strike]
    else
      complete_puts << create_synthetic_option(
        underlying_symbol: underlying_symbol,
        strike: strike,
        contract_type: 'PUT',
        underlying_price: underlying_price,
        days_to_expiration: dte,
        expiration_date: expiration_date,
        mark: (strike == min_strike ? DEFAULT_MIN_MARK : nil),
        feature_values: feature_values
      )
    end
  end

  [complete_calls, complete_puts]
end

def create_synthetic_option(
  underlying_symbol:,strike:, contract_type:, underlying_price:, days_to_expiration:, expiration_date:, mark: nil, feature_values: nil
)
  option = DataObjects::Option.new(
    symbol: create_option_symbol(underlying_symbol, strike, contract_type, expiration_date),
    underlying_symbol: underlying_symbol,
    strike: strike,
    put_call: contract_type,
    mark: mark,
    underlying_price: underlying_price,
    expiration_date: expiration_date,
    days_to_expiration: days_to_expiration,
    delta: nil,
    open_interest: 0,
    total_volume: 1,
    timestamp: @datetime
  )

  if feature_values
    feature_values.each do |key, value|
      option.set_feature(key, value)
    end
  end

  option
end

def create_option_symbol(underlying_symbol, strike, contract_type, expiration_date)
  normalized = underlying_symbol.to_s.sub(/\A[\^\$]/, '')
  exp_str = expiration_date.to_s.tr('-', '')
  contract_letter = contract_type[0]
  strike_str = (strike * 1000).to_i.to_s.rjust(8, '0')
  "#{normalized}#{exp_str}#{contract_letter}#{strike_str}"
end
```

### Step 3: OptionsTrader::SyntheticData::Transform::LinearInterpolator

Updating the price interpolator. It should assume that the prices provided are already monotonic. We should check though and raise an error if they are not monotonic. The price interpolator should only generate prices for options that have a null price/mark. Here are some contraints and details that the price interpolator needs to follow:
- The default min extrinsic price is 0.025.
- Separate the options into ITM and OTM.
- For the OTM optins, just linearly interpolate the price for strikes missing marks (since the price/mark is just the extrinsic value of the option).
- For the ITM options we need to handle both the extrinsic and intrinsic value. First, linearly interpolate the extrinsic value for the options that are missing a mark/price. Set the extrinsic value on the option. Then actually, let's jsut the @option.rb data object. I think it will just handle calculating the mark once we provide the extrinsic value.

Renamed PriceInterpolator to LinearInterpolator


- For ITM options we should first find the extrinsic value for those options that we have prices for.
  - For Calls: `extrinsic value = mark - (underlying_price - strike)`
  - For puts:  `extrinsic value = mark - (strike - underlying_price)`
  - Then linearly interpolate the extrinsic value
- OTM
  - For the PUT with
- First find the ATM straddle price of the option chain by finding the call and put (that has a price) that's closest to the underlying price. Use the ATM straddle price as a proxy for 1 standard deviation move up or down from the current spot price of the underlying

### Step 4: Other Considerations

- We need to enforce the .with_features method on the OptionChainPipeline needs to be called first in the pipeline. We should raise an error if it is not called first. So we will need to probably set some sort of instance var in the OptionChainPipeline object once the pipeline is started and we need to check the value of this instance var inside the .with_feature method to ensure that it is not getting called somewhere in the middle of the pipeline.

## Architecture

### Namespace: `OptionsTrader::SyntheticData`

```
lib/options_trader/synthetic_chain/
  pipeline.rb              # Main orchestrator
  monotonicity_enforcer.rb # Enforces no-arbitrage price constraints
  strike_completer.rb      # Generates synthetic options for missing strikes
  price_interpolator.rb    # Interpolates missing option prices
  delta_enricher.rb        # Enriches options with predicted deltas
```

### Core Class: Pipeline

```ruby
module OptionsTrader
  module SyntheticData
    class OptionChainPipeline
      def initialize(option_chain, context: {})
        # context includes: underlying_price, dte, expiration_date, valid_time
      end

      # Transformation stages (order-dependent)
      def complete_strikes(min_strike:, max_strike:, **opts)
      def interpolate_prices
      def enforce_monotonicity
      def enrich_deltas(predictor:)

      def build # Returns transformed OptionsChain

    end
  end
end
```

## Transformation Stages

### 1. StrikeCompleter
- Generates target strikes with dense ATM spacing, wider OTM spacing
- Creates synthetic Option objects for missing strikes
- Propagates market features (VIX, skew) to synthetic options
- Sets boundary conditions (min mark for extreme strikes)

### 2. PriceInterpolator
- Wrapper around `SyntheticData::Utils::PriceInterpolator`
- Fills nil marks via linear interpolation between known prices
- Extrapolates using slope from nearest two points

### 3. MonotonicityEnforcer
- Wrapper around `SyntheticData::Utils::MonotonicityEnforcer`
- Enforces no-arbitrage constraints:
  - Calls: mark[i] > mark[i+1] (decreasing with strike)
  - Puts: mark[i] < mark[i+1] (increasing with strike)

### 4. DeltaEnricher
- Adapter for `Services::DeltaEnricher`
- Predicts deltas using ML model (GreekForge)
- Requires: dte, moneyness, mark, strike, underlying_price, vix9d, vvix

## Pipeline Dependencies

```
enforce_monotonicity → complete_strikes → interpolate_prices → enrich_deltas
```

**Critical Dependencies:**
- Monotonicity must precede interpolation
- Strike completion must precede interpolation (all strikes must exist)
- Monotonicity must precede delta enrichment (predictor requires valid prices)

## Usage

### Custom OptionChain Pipeline

```ruby
context = {
  underlying_price: raw_chain.underlying_price,
  dte: 1,
  expiration_date: date,
  valid_time: timestamp
}

complete_chain = SyntheticData::OptionChainPipeline.new(raw_chain, context: context)
  .enforce_monotonicity
  .with_features(quotes) # queried from price_history prior to running the pipeline, added to each option as a feature
  .complete_strikes(min_strike: 5500, max_strike: 6000)
  .interpolate_prices
  .enrich_deltas(predictor: greek_forge)
  .build
```

### Partial Pipeline (No Deltas)

```ruby
chain = SyntheticData::OptionChainPipeline.new(raw_chain, context: context)
  .enforce_monotonicity
  .complete_strikes
  .interpolate_prices
  .build
```

## Context Hash

The pipeline requires a context hash with metadata about the chain:

```ruby
{
  underlying_price: Float,   # Current underlying price
  dte: Integer,             # Days to expiration
  expiration_date: Date,    # Option expiration date
  valid_time: Time          # Timestamp for historical snapshot
}
```

## Integration with HistoricalSnapshot

```ruby
# HistoricalSnapshot simplified to data fetching only
snapshot = Services::HistoricalSnapshot.new(valid_time: time)
raw_chain = snapshot.get_option_chain('SPXW', expiration_date: date)
quotes = snapshot.get_quotes(['$VIX9D', '$VVIX'])

# Pipeline handles all transformations
complete_chain = SyntheticData::OptionChainPipeline.new(raw_chain, context: context)
  .enforce_monotonicity
  .complete_strikes(min_strike: 5500, max_strike: 6000)
  .interpolate_prices
  .enrich_deltas(predictor: greek_forge, features: quotes)
  .build
```

### Code from the Old Pipeline removed from the HistoricalSnapshot Service

```ruby
# Strike generation defaults
DEFAULT_MIN_OFFSET = -3000
DEFAULT_MAX_OFFSET = 1000
DEFAULT_INNER_OFFSET = 225
DEFAULT_INNER_STEP = 5
DEFAULT_OUTER_STEP = 25

# Step 2: Convert to arrays and extract underlying price
call_opts, put_opts, underlying_price, dte = partition_records(records)

# Step 2.5: Extract feature values from first record (all records have same feature values)
feature_values = extract_feature_values(records.first) if features.any?

# Step 3: Generate target strikes if not provided
target_strikes = generate_target_strikes(
  underlying_price, min_strike: min_strike, max_strike: max_strike
)

# Step 4: Build complete option arrays with synthetic options
complete_calls, complete_puts = build_complete_option_arrays(
  underlying_symbol, call_opts, put_opts, target_strikes, underlying_price, dte, expiration_date, feature_values
)

# Step 5: Interpolate missing prices and enforce monotonicity
complete_calls = Utils::OptionPriceInterpolator.interpolate(complete_calls, contract_type: 'CALL').then do |opts|
  Utils::MonotonicityEnforcer.enforce(opts, contract_type: 'CALL')
end
complete_puts = Utils::OptionPriceInterpolator.interpolate(complete_puts, contract_type: 'PUT').then do |opts|
  Utils::MonotonicityEnforcer.enforce(opts, contract_type: 'PUT')
end

def extract_feature_values(record)
  return {} if record.nil?

  feature_hash = {}
  record.each do |key, value|
    # Skip standard option fields
    next if %w[symbol strike contract_type expiration_date mark volume open_price
               close_price high_price low_price valid_time dte underlying_price moneyness].include?(key)
    # Collect feature values (vix9d, vvix, skew, etc.)
    feature_hash[key] = value&.to_f if value
  end
  feature_hash
end

def partition_records(records)
  underlying_price = records.first&.dig('underlying_price')&.to_f
  dte = records.first&.dig('dte')&.to_i

  options = records.map { |record| build_option_from_record(record) }

  call_opts, put_opts = options.partition { |option| option.put_call == 'CALL' }

  [call_opts, put_opts, underlying_price, dte]
end

# Generates strike prices with dense spacing near ATM and wider spacing OTM.
# Inner strikes use 5-point increments, outer strikes use 25-point increments.
def generate_target_strikes(
  underlying_price,
  min_strike: nil,
  max_strike: nil,
  min_offset: DEFAULT_MIN_OFFSET,
  max_offset: DEFAULT_MAX_OFFSET,
  inner_offset: DEFAULT_INNER_OFFSET,
  inner_step: DEFAULT_INNER_STEP,
  outer_step: DEFAULT_OUTER_STEP
)
  # Round underlying to nearest outer_step
  base_strike = (underlying_price / outer_step.to_f).round * outer_step

  unless min_strike.present? && max_strike.present?
    min_strike = base_strike + min_offset
    max_strike = base_strike + max_offset
  end

  inner_min_strike = base_strike - inner_offset
  inner_max_strike = base_strike + inner_offset

  # Align inner_max_strike to outer_step boundary
  while inner_max_strike % outer_step != 0
    inner_max_strike += inner_step
  end

  strikes = []
  current_strike = min_strike

  while current_strike <= max_strike
    strikes << current_strike
    step = (current_strike >= inner_min_strike && current_strike < inner_max_strike) ? inner_step : outer_step
    current_strike += step
  end

  strikes.sort
end

# Merges existing options with synthetic options for missing strikes.
# Synthetic options carry the same feature values as real options.
def build_complete_option_arrays(
  underlying_symbol, calls, puts,
  target_strikes, underlying_price, dte, expiration_date, feature_values = nil
)
  min_strike = target_strikes.min
  max_strike = target_strikes.max
  calls_by_strike = calls.index_by(&:strike)
  puts_by_strike = puts.index_by(&:strike)

  complete_calls = []
  complete_puts = []

  target_strikes.each do |strike|
    if calls_by_strike[strike]
      complete_calls << calls_by_strike[strike]
    else
      complete_calls << create_synthetic_option(
        underlying_symbol: underlying_symbol,
        strike: strike,
        contract_type: 'CALL',
        underlying_price: underlying_price,
        days_to_expiration: dte,
        expiration_date: expiration_date,
        mark: (strike == max_strike ? DEFAULT_MIN_MARK : nil),
        feature_values: feature_values
      )
    end

    if puts_by_strike[strike]
      complete_puts << puts_by_strike[strike]
    else
      complete_puts << create_synthetic_option(
        underlying_symbol: underlying_symbol,
        strike: strike,
        contract_type: 'PUT',
        underlying_price: underlying_price,
        days_to_expiration: dte,
        expiration_date: expiration_date,
        mark: (strike == min_strike ? DEFAULT_MIN_MARK : nil),
        feature_values: feature_values
      )
    end
  end

  [complete_calls, complete_puts]
end

# Creates a synthetic option for a missing strike. Features are copied from real options
# to ensure consistent market context across the entire chain.
def create_synthetic_option(
  underlying_symbol:,strike:, contract_type:, underlying_price:, days_to_expiration:, expiration_date:, mark: nil, feature_values: nil
)
  option = DataObjects::Option.new(
    symbol: create_option_symbol(underlying_symbol, strike, contract_type, expiration_date),
    underlying_symbol: underlying_symbol,
    strike: strike,
    put_call: contract_type,
    mark: mark,
    underlying_price: underlying_price,
    expiration_date: expiration_date,
    days_to_expiration: days_to_expiration,
    delta: nil,
    open_interest: 0,
    total_volume: 1,
    timestamp: @datetime
  )

  if feature_values
    feature_values.each do |key, value|
      option.set_feature(key, value)
    end
  end

  option
end

def create_option_symbol(underlying_symbol, strike, contract_type, expiration_date)
  normalized = underlying_symbol.to_s.sub(/\A[\^\$]/, '')
  exp_str = expiration_date.to_s.tr('-', '')
  contract_letter = contract_type[0]
  strike_str = (strike * 1000).to_i.to_s.rjust(8, '0')
  "#{normalized}#{exp_str}#{contract_letter}#{strike_str}"
end
```