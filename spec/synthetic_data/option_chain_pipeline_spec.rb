require 'spec_helper'

RSpec.describe OptionsTrader::SyntheticData::OptionChainPipeline do
  let(:underlying_price) { 5900.0 }
  let(:underlying_symbol) { 'SPXW' }
  let(:expiration_date) { Date.new(2025, 10, 17) }
  let(:dte) { 1 }
  let(:timestamp) { Time.now }

  let(:context) do
    {
      underlying_price: underlying_price,
      underlying_symbol: underlying_symbol,
      dte: dte,
      expiration_date: expiration_date,
      valid_time: timestamp
    }
  end

  def create_option(strike:, contract_type:, mark: nil, features: {})
    option = OptionsTrader::DataObjects::Option.new(
      symbol: "SPXW#{expiration_date.strftime('%Y%m%d')}#{contract_type[0]}#{(strike * 1000).to_i.to_s.rjust(8, '0')}",
      underlying_symbol: underlying_symbol,
      strike: strike,
      put_call: contract_type,
      mark: mark,
      underlying_price: underlying_price,
      expiration_date: expiration_date,
      days_to_expiration: dte,
      timestamp: timestamp
    )

    features.each do |key, value|
      option.set_feature(key, value)
    end

    option
  end

  # Underlying price: 5900
  # For realistic prices:
  # - ITM calls (strikes < 5900): mark = intrinsic + extrinsic
  #   - 5800: intrinsic=100, extrinsic~=20, mark=120
  #   - 5850: intrinsic=50, extrinsic~=25, mark=75
  # - ATM/OTM calls (strikes >= 5900): mark = extrinsic only
  #   - 5900: extrinsic~=28, mark=28
  #   - 5950: extrinsic~=10, mark=10
  # Marks should be monotonically decreasing: 120 > 75 > 28 > 10 ✓
  let(:raw_call_opts) do
    [
      create_option(strike: 5800, contract_type: 'CALL', mark: 120.0),  # ITM: 100 intrinsic + 20 extrinsic
      create_option(strike: 5850, contract_type: 'CALL', mark: 75.0),   # ITM: 50 intrinsic + 25 extrinsic
      create_option(strike: 5900, contract_type: 'CALL', mark: 28.0),   # ATM: 28 extrinsic
      create_option(strike: 5950, contract_type: 'CALL', mark: 10.0)    # OTM: 10 extrinsic
    ]
  end

  # For puts (underlying = 5900):
  # - OTM puts (strikes < 5900): mark = extrinsic only
  #   - 5800: extrinsic~=10, mark=10
  #   - 5850: extrinsic~=20, mark=20
  # - ATM/ITM puts (strikes >= 5900): mark = intrinsic + extrinsic
  #   - 5900: extrinsic~=28, mark=28
  #   - 5950: intrinsic=50, extrinsic~=25, mark=75
  # Marks should be monotonically increasing: 10 < 20 < 28 < 75 ✓
  let(:raw_put_opts) do
    [
      create_option(strike: 5800, contract_type: 'PUT', mark: 10.0),    # OTM: 10 extrinsic
      create_option(strike: 5850, contract_type: 'PUT', mark: 20.0),    # OTM: 20 extrinsic
      create_option(strike: 5900, contract_type: 'PUT', mark: 28.0),    # ATM: 28 extrinsic
      create_option(strike: 5950, contract_type: 'PUT', mark: 75.0)     # ITM: 50 intrinsic + 25 extrinsic
    ]
  end

  let(:raw_chain) do
    OptionsTrader::DataObjects::OptionsChain.new(
      symbol: underlying_symbol,
      underlying_price: underlying_price,
      call_opts: raw_call_opts,
      put_opts: raw_put_opts
    )
  end

  describe '#initialize' do
    it 'validates required context keys' do
      expect {
        described_class.new(raw_chain, context: {})
      }.to raise_error(OptionsTrader::SyntheticData::OptionChainPipeline::MissingContextError, /Missing required context keys/)
    end

    it 'accepts valid context' do
      expect {
        described_class.new(raw_chain, context: context)
      }.not_to raise_error
    end

    it 'creates a copy of the options arrays' do
      pipeline = described_class.new(raw_chain, context: context)
      built_chain = pipeline.build

      # Should not modify original arrays
      expect(built_chain.call_opts.object_id).not_to eq(raw_call_opts.object_id)
      expect(built_chain.put_opts.object_id).not_to eq(raw_put_opts.object_id)
    end
  end

  describe '#with_features' do
    it 'allows setting features before pipeline starts' do
      features = { vix9d: 18.5, vvix: 85.2 }

      pipeline = described_class.new(raw_chain, context: context)
        .with_features(features)

      expect(pipeline).to be_a(described_class)
    end

    it 'raises error if called after transformations' do
      features = { vix9d: 18.5 }

      expect {
        described_class.new(raw_chain, context: context)
          .enforce_monotonicity
          .with_features(features)
      }.to raise_error(OptionsTrader::SyntheticData::OptionChainPipeline::PipelineStateError, /.with_features must be called before any transformations/)
    end
  end

  describe '#enforce_monotonicity' do
    let(:monotonic_call_opts) do
      [
        create_option(strike: 5800, contract_type: 'CALL', mark: 120.0),
        create_option(strike: 5850, contract_type: 'CALL', mark: 80.0),
        create_option(strike: 5900, contract_type: 'CALL', mark: 81.0), # Violation: should be < 80.0
        create_option(strike: 5950, contract_type: 'CALL', mark: 30.0)
      ]
    end

    let(:chain_with_violations) do
      OptionsTrader::DataObjects::OptionsChain.new(
        symbol: underlying_symbol,
        underlying_price: underlying_price,
        call_opts: monotonic_call_opts,
        put_opts: raw_put_opts
      )
    end

    it 'enforces monotonicity on call options' do
      result = described_class.new(chain_with_violations, context: context)
        .enforce_monotonicity
        .build

      call_marks = result.call_opts.sort_by(&:strike).map(&:mark)

      # Verify monotonicity: each mark should be less than the previous
      call_marks.each_cons(2) do |prev_mark, curr_mark|
        expect(curr_mark).to be < prev_mark
      end
    end

    it 'supports method chaining' do
      pipeline = described_class.new(raw_chain, context: context)
        .enforce_monotonicity

      expect(pipeline).to be_a(described_class)
    end

    it 'accepts method parameter' do
      result = described_class.new(chain_with_violations, context: context)
        .enforce_monotonicity(method: 'remove')
        .build

      # Verify that violations were handled (either adjusted or removed)
      expect(result.call_opts).not_to be_empty
    end
  end

  describe '#complete_strikes' do
    it 'adds missing strikes to the chain' do
      result = described_class.new(raw_chain, context: context)
        .complete_strikes(min_strike: 5800, max_strike: 5950)
        .build

      call_strikes = result.call_opts.map(&:strike).sort
      put_strikes = result.put_opts.map(&:strike).sort

      # Should have more strikes than the original chain
      expect(call_strikes.length).to be > raw_call_opts.length
      expect(put_strikes.length).to be > raw_put_opts.length

      # Should include all original strikes
      expect(call_strikes).to include(5800, 5850, 5900, 5950)
      expect(put_strikes).to include(5800, 5850, 5900, 5950)
    end

    it 'preserves existing option data' do
      result = described_class.new(raw_chain, context: context)
        .complete_strikes(min_strike: 5800, max_strike: 5950)
        .build

      existing_call = result.call_opts.find { |c| c.strike == 5850 }
      expect(existing_call.mark).to eq(80.0)
    end

    it 'creates synthetic options with nil marks' do
      result = described_class.new(raw_chain, context: context)
        .complete_strikes(min_strike: 5800, max_strike: 5950)
        .build

      # Find a strike that wasn't in the original chain
      synthetic_call = result.call_opts.find { |c| c.strike == 5805 }
      expect(synthetic_call).not_to be_nil
      expect(synthetic_call.mark).to be_nil
    end

    it 'supports method chaining' do
      pipeline = described_class.new(raw_chain, context: context)
        .complete_strikes(min_strike: 5800, max_strike: 5950)

      expect(pipeline).to be_a(described_class)
    end

    it 'respects custom strike parameters' do
      result = described_class.new(raw_chain, context: context)
        .complete_strikes(
          min_strike: 5700,
          max_strike: 6000,
          inner_step: 10
        )
        .build

      call_strikes = result.call_opts.map(&:strike).sort

      expect(call_strikes.min).to eq(5700)
      expect(call_strikes.max).to eq(6000)
    end
  end

  describe '#interpolate_prices' do
    it 'interpolates missing prices in the option chain' do
      # First add strikes which creates options with nil marks
      result = described_class.new(raw_chain, context: context)
        .complete_strikes(min_strike: 5800, max_strike: 5950)
        .interpolate_prices
        .build

      # All options should have marks after interpolation
      call_marks = result.call_opts.map(&:mark)
      put_marks = result.put_opts.map(&:mark)

      expect(call_marks).to all(be_a(Numeric))
      expect(put_marks).to all(be_a(Numeric))
      expect(call_marks).not_to include(nil)
      expect(put_marks).not_to include(nil)
    end

    it 'maintains monotonicity after full pipeline with enforce -> complete -> interpolate' do
      result = described_class.new(raw_chain, context: context)
        .enforce_monotonicity(method: 'remove')
        .complete_strikes(min_strike: 5800, max_strike: 5950)
        .interpolate_prices
        .build

      # Verify call options are monotonically decreasing (higher strikes = lower prices)
      call_marks = result.call_opts.sort_by(&:strike).map(&:mark).compact
      call_marks.each_cons(2) do |prev_mark, curr_mark|
        expect(curr_mark).to be <= prev_mark
      end

      # Verify put options are monotonically increasing (higher strikes = higher prices)
      put_marks = result.put_opts.sort_by(&:strike).map(&:mark).compact
      put_marks.each_cons(2) do |prev_mark, curr_mark|
        expect(curr_mark).to be >= prev_mark
      end
    end

    it 'supports method chaining' do
      pipeline = described_class.new(raw_chain, context: context)
        .interpolate_prices

      expect(pipeline).to be_a(described_class)
    end

    it 'accepts custom min_extrinsic parameter' do
      result = described_class.new(raw_chain, context: context)
        .complete_strikes(min_strike: 5800, max_strike: 5950)
        .interpolate_prices(min_extrinsic: 0.05)
        .build

      # All options should have marks
      expect(result.call_opts.map(&:mark)).to all(be_a(Numeric))
      expect(result.put_opts.map(&:mark)).to all(be_a(Numeric))
    end

    it 'handles non-monotonic input when enforce_monotonicity is used first' do
      # Create a chain with non-monotonic prices
      non_monotonic_calls = [
        create_option(strike: 5800, contract_type: 'CALL', mark: 120.0),
        create_option(strike: 5850, contract_type: 'CALL', mark: 150.0), # violation
        create_option(strike: 5900, contract_type: 'CALL', mark: 50.0)
      ]

      bad_chain = OptionsTrader::DataObjects::OptionsChain.new(
        symbol: underlying_symbol,
        underlying_price: underlying_price,
        call_opts: non_monotonic_calls,
        put_opts: raw_put_opts
      )

      # Should work when we enforce monotonicity first with 'remove' method
      result = described_class.new(bad_chain, context: context)
        .enforce_monotonicity(method: 'remove')
        .complete_strikes(min_strike: 5800, max_strike: 5950)
        .interpolate_prices
        .build

      # Verify final output is monotonic
      call_marks = result.call_opts.sort_by(&:strike).map(&:mark).compact
      if call_marks.length > 1
        call_marks.each_cons(2) do |prev_mark, curr_mark|
          expect(curr_mark).to be <= prev_mark
        end
      end
    end
  end

  describe '#build' do
    it 'returns a DataObjects::OptionsChain' do
      result = described_class.new(raw_chain, context: context).build

      expect(result).to be_a(OptionsTrader::DataObjects::OptionsChain)
    end

    it 'preserves the underlying symbol' do
      result = described_class.new(raw_chain, context: context).build

      expect(result.symbol).to eq(underlying_symbol)
    end

    it 'uses context underlying price' do
      custom_context = context.merge(underlying_price: 6000.0)
      result = described_class.new(raw_chain, context: custom_context).build

      expect(result.underlying_price).to eq(6000.0)
    end
  end

  describe 'full pipeline integration' do
    let(:features) { { vix9d: 18.5, vvix: 85.2, skew: 120.0 } }

    it 'runs a complete transformation pipeline: with_features -> enforce_monotonicity -> complete_strikes -> interpolate_prices' do
      result = described_class.new(raw_chain, context: context)
        .with_features(features)
        .enforce_monotonicity(method: 'remove')
        .complete_strikes(min_strike: 5750, max_strike: 6000)
        .interpolate_prices
        .build

      # Verify the result is a valid option chain
      expect(result).to be_a(OptionsTrader::DataObjects::OptionsChain)
      expect(result.call_opts).not_to be_empty
      expect(result.put_opts).not_to be_empty

      # Verify monotonicity is maintained in final output (use compact to skip nils)
      call_marks_sorted = result.call_opts.sort_by(&:strike).map(&:mark).compact
      if call_marks_sorted.length > 1
        call_marks_sorted.each_cons(2) do |prev_mark, curr_mark|
          expect(curr_mark).to be <= prev_mark
        end
      end

      put_marks_sorted = result.put_opts.sort_by(&:strike).map(&:mark).compact
      if put_marks_sorted.length > 1
        put_marks_sorted.each_cons(2) do |prev_mark, curr_mark|
          expect(curr_mark).to be >= prev_mark
        end
      end

      # Verify strikes were added
      expect(result.call_opts.length).to be > raw_call_opts.length
      expect(result.put_opts.length).to be > raw_put_opts.length

      # Verify features were propagated to synthetic options
      synthetic_call = result.call_opts.find { |c| c.strike == 5755 }
      if synthetic_call
        expect(synthetic_call.has_feature?(:vix9d)).to be true
        expect(synthetic_call.vix9d).to eq(18.5)
      end
    end

    it 'runs a complete transformation pipeline with enforce_monotonicity and complete_strikes (without interpolation)' do
      result = described_class.new(raw_chain, context: context)
        .with_features(features)
        .enforce_monotonicity
        .complete_strikes(min_strike: 5750, max_strike: 6000)
        .build

      # Verify the result is a valid option chain
      expect(result).to be_a(OptionsTrader::DataObjects::OptionsChain)
      expect(result.call_opts).not_to be_empty
      expect(result.put_opts).not_to be_empty

      # Verify monotonicity
      call_marks = result.call_opts.sort_by(&:strike).map(&:mark).compact
      call_marks.each_cons(2) do |prev_mark, curr_mark|
        expect(curr_mark).to be < prev_mark
      end

      put_marks = result.put_opts.sort_by(&:strike).map(&:mark).compact
      put_marks.each_cons(2) do |prev_mark, curr_mark|
        expect(curr_mark).to be > prev_mark
      end

      # Verify strikes were added
      expect(result.call_opts.length).to be > raw_call_opts.length
      expect(result.put_opts.length).to be > raw_put_opts.length

      # Verify features were propagated to synthetic options
      synthetic_call = result.call_opts.find { |c| c.strike == 5755 }
      if synthetic_call
        expect(synthetic_call.has_feature?(:vix9d)).to be true
        expect(synthetic_call.vix9d).to eq(18.5)
      end
    end

    it 'works with enforce_monotonicity then complete_strikes order' do
      result = described_class.new(raw_chain, context: context)
        .enforce_monotonicity
        .complete_strikes(min_strike: 5800, max_strike: 5950)
        .build

      expect(result.call_opts.length).to be > raw_call_opts.length
      expect(result.put_opts.length).to be > raw_put_opts.length
    end

    it 'works with just enforce_monotonicity' do
      result = described_class.new(raw_chain, context: context)
        .enforce_monotonicity
        .build

      # Should have same number of options, just with enforced monotonicity
      expect(result.call_opts.length).to eq(raw_call_opts.length)
      expect(result.put_opts.length).to eq(raw_put_opts.length)
    end

    it 'works with just complete_strikes' do
      result = described_class.new(raw_chain, context: context)
        .complete_strikes(min_strike: 5800, max_strike: 5950)
        .build

      expect(result.call_opts.length).to be > raw_call_opts.length
      expect(result.put_opts.length).to be > raw_put_opts.length
    end

    it 'works with no transformations (passthrough)' do
      result = described_class.new(raw_chain, context: context).build

      expect(result.call_opts.length).to eq(raw_call_opts.length)
      expect(result.put_opts.length).to eq(raw_put_opts.length)
    end
  end

  describe 'edge cases' do
    context 'with empty option chain' do
      let(:empty_chain) do
        OptionsTrader::DataObjects::OptionsChain.new(
          symbol: underlying_symbol,
          underlying_price: underlying_price,
          call_opts: [],
          put_opts: []
        )
      end

      it 'can add strikes to an empty chain' do
        result = described_class.new(empty_chain, context: context)
          .complete_strikes(min_strike: 5800, max_strike: 5900)
          .build

        expect(result.call_opts).not_to be_empty
        expect(result.put_opts).not_to be_empty
      end
    end

    context 'with single option' do
      let(:single_option_chain) do
        OptionsTrader::DataObjects::OptionsChain.new(
          symbol: underlying_symbol,
          underlying_price: underlying_price,
          call_opts: [create_option(strike: 5900, contract_type: 'CALL', mark: 50.0)],
          put_opts: [create_option(strike: 5900, contract_type: 'PUT', mark: 50.0)]
        )
      end

      it 'can build a complete chain from a single option' do
        result = described_class.new(single_option_chain, context: context)
          .complete_strikes(min_strike: 5800, max_strike: 6000)
          .build

        expect(result.call_opts.length).to be > 1
        expect(result.put_opts.length).to be > 1
      end
    end
  end
end
