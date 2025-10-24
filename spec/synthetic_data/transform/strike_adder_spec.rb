require 'spec_helper'

RSpec.describe OptionsTrader::SyntheticData::Transform::StrikeAdder do
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
      expiration_date: expiration_date
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

  describe '.add_strikes' do
    context 'with sparse existing options' do
      let(:call_opts) do
        [
          create_option(strike: 5800, contract_type: 'CALL', mark: 120.0),
          create_option(strike: 5900, contract_type: 'CALL', mark: 60.0)
        ]
      end

      let(:put_opts) do
        [
          create_option(strike: 5800, contract_type: 'PUT', mark: 40.0),
          create_option(strike: 5900, contract_type: 'PUT', mark: 80.0)
        ]
      end

      it 'returns a hash with :calls and :puts keys' do
        result = described_class.add_strikes(
          calls: call_opts,
          puts: put_opts,
          context: context,
          features: {},
          min_strike: 5800,
          max_strike: 5900
        )

        expect(result).to be_a(Hash)
        expect(result).to have_key(:calls)
        expect(result).to have_key(:puts)
      end

      it 'fills in missing strikes between existing options' do
        result = described_class.add_strikes(
          calls: call_opts,
          puts: put_opts,
          context: context,
          features: {},
          min_strike: 5800,
          max_strike: 5900
        )

        # Should have strikes from 5800 to 5900 in 5-point increments (ATM range)
        call_strikes = result[:calls].map(&:strike).sort
        put_strikes = result[:puts].map(&:strike).sort

        expect(call_strikes).to eq(put_strikes)
        expect(call_strikes).to include(5800, 5805, 5810, 5815, 5820, 5825, 5830, 5835, 5840, 5845, 5850, 5855, 5860, 5865, 5870, 5875, 5880, 5885, 5890, 5895, 5900)
      end

      it 'preserves existing option data' do
        result = described_class.add_strikes(
          calls: call_opts,
          puts: put_opts,
          context: context,
          features: {},
          min_strike: 5800,
          max_strike: 5900
        )

        existing_call_5800 = result[:calls].find { |c| c.strike == 5800 }
        expect(existing_call_5800.mark).to eq(120.0)
        expect(existing_call_5800.symbol).to eq(calls[0].symbol)

        existing_put_5900 = result[:puts].find { |p| p.strike == 5900 }
        expect(existing_put_5900.mark).to eq(80.0)
      end

      it 'creates synthetic options with nil marks for missing strikes' do
        result = described_class.add_strikes(
          calls: call_opts,
          puts: put_opts,
          context: context,
          features: {},
          min_strike: 5800,
          max_strike: 5900
        )

        synthetic_call_5850 = result[:calls].find { |c| c.strike == 5850 }
        expect(synthetic_call_5850).not_to be_nil
        expect(synthetic_call_5850.mark).to be_nil
        expect(synthetic_call_5850.put_call).to eq('CALL')
        expect(synthetic_call_5850.underlying_price).to eq(underlying_price)
        expect(synthetic_call_5850.days_to_expiration).to eq(dte)
      end

      it 'sets boundary marks for extreme strikes' do
        result = described_class.add_strikes(
          calls: call_opts,
          puts: put_opts,
          context: context,
          features: {},
          min_strike: 5700,
          max_strike: 6000
        )

        # Max strike call should have DEFAULT_MIN_MARK
        max_call = result[:calls].find { |c| c.strike == 6000 }
        expect(max_call.mark).to eq(described_class::DEFAULT_MIN_MARK)

        # Min strike put should have DEFAULT_MIN_MARK
        min_put = result[:puts].find { |p| p.strike == 5700 }
        expect(min_put.mark).to eq(described_class::DEFAULT_MIN_MARK)
      end
    end

    context 'with feature propagation' do
      let(:features) { { vix9d: 18.5, vvix: 85.2, skew: 120.0 } }

      let(:call_opts) do
        [create_option(strike: 5900, contract_type: 'CALL', mark: 60.0, features: features)]
      end

      let(:put_opts) do
        [create_option(strike: 5900, contract_type: 'PUT', mark: 80.0, features: features)]
      end

      it 'propagates features from existing options to synthetic options' do
        result = described_class.add_strikes(
          calls: call_opts,
          puts: put_opts,
          context: context,
          features: features,
          min_strike: 5850,
          max_strike: 5950
        )

        synthetic_call = result[:calls].find { |c| c.strike == 5875 }
        expect(synthetic_call.has_feature?(:vix9d)).to be true
        expect(synthetic_call.vix9d).to eq(18.5)
        expect(synthetic_call.has_feature?(:vvix)).to be true
        expect(synthetic_call.vvix).to eq(85.2)
        expect(synthetic_call.has_feature?(:skew)).to be true
        expect(synthetic_call.skew).to eq(120.0)
      end
    end

    context 'with default strike generation' do
      let(:call_opts) do
        [create_option(strike: 5900, contract_type: 'CALL', mark: 60.0)]
      end

      let(:put_opts) do
        [create_option(strike: 5900, contract_type: 'PUT', mark: 80.0)]
      end

      it 'generates strikes using default offsets when min/max not provided' do
        result = described_class.add_strikes(
          calls: call_opts,
          puts: put_opts,
          context: context,
          features: {}
        )

        call_strikes = result[:calls].map(&:strike).sort

        # Should include strikes from base_strike + DEFAULT_MIN_OFFSET to base_strike + DEFAULT_MAX_OFFSET
        # base_strike for 5900.0 with outer_step 25 is 5900
        # min_strike = 5900 + (-3000) = 2900
        # max_strike = 5900 + 1000 = 6900
        expect(call_strikes.min).to eq(2900)
        expect(call_strikes.max).to eq(6900)
      end

      it 'uses dense spacing (5 points) within ATM range' do
        result = described_class.add_strikes(
          calls: call_opts,
          puts: put_opts,
          context: context,
          features: {},
          min_strike: 5800,
          max_strike: 6000
        )

        call_strikes = result[:calls].map(&:strike).sort

        # Within ATM range (5900 - 225 to 5900 + 225), strikes should be 5 points apart
        atm_strikes = call_strikes.select { |s| s >= 5675 && s <= 6125 }
        diffs = atm_strikes.each_cons(2).map { |a, b| b - a }

        # Most diffs should be 5 (some might be at boundary)
        expect(diffs.count(5)).to be > diffs.count(25)
      end

      it 'uses wide spacing (25 points) outside ATM range' do
        result = described_class.add_strikes(
          calls: call_opts,
          puts: put_opts,
          context: context,
          features: {},
          min_strike: 5000,
          max_strike: 5600
        )

        call_strikes = result[:calls].map(&:strike).sort

        # Outside ATM range, strikes should be 25 points apart
        otm_strikes = call_strikes.select { |s| s < 5675 }
        diffs = otm_strikes.each_cons(2).map { |a, b| b - a }

        expect(diffs.uniq).to include(25)
      end
    end

    context 'with custom strike parameters' do
      let(:call_opts) do
        [create_option(strike: 5900, contract_type: 'CALL', mark: 60.0)]
      end

      let(:put_opts) do
        [create_option(strike: 5900, contract_type: 'PUT', mark: 80.0)]
      end

      it 'respects custom inner_step parameter' do
        result = described_class.add_strikes(
          calls: call_opts,
          puts: put_opts,
          context: context,
          features: {},
          min_strike: 5800,
          max_strike: 6000,
          inner_step: 10
        )

        call_strikes = result[:calls].map(&:strike).sort

        # Within ATM range, strikes should be 10 points apart
        atm_strikes = call_strikes.select { |s| s >= 5675 && s <= 6125 }
        diffs = atm_strikes.each_cons(2).map { |a, b| b - a }

        expect(diffs).to include(10)
      end

      it 'respects custom outer_step parameter' do
        result = described_class.add_strikes(
          calls: call_opts,
          puts: put_opts,
          context: context,
          features: {},
          min_strike: 5000,
          max_strike: 5600,
          outer_step: 50
        )

        call_strikes = result[:calls].map(&:strike).sort

        # Outside ATM range, strikes should be 50 points apart
        otm_strikes = call_strikes.select { |s| s < 5675 }
        diffs = otm_strikes.each_cons(2).map { |a, b| b - a }

        expect(diffs.uniq).to include(50)
      end
    end

    context 'with empty option arrays' do
      it 'creates synthetic options when calls and puts are empty' do
        result = described_class.add_strikes(
          calls: [],
          puts: [],
          context: context,
          features: {},
          min_strike: 5850,
          max_strike: 5950
        )

        expect(result[:calls]).not_to be_empty
        expect(result[:puts]).not_to be_empty

        # All options should be synthetic with nil marks (except boundaries)
        non_boundary_calls = result[:calls].select { |c| c.strike != 5950 }
        non_boundary_puts = result[:puts].select { |p| p.strike != 5850 }

        expect(non_boundary_calls.all? { |c| c.mark.nil? }).to be true
        expect(non_boundary_puts.all? { |p| p.mark.nil? }).to be true
      end
    end
  end

  describe '#create_option_symbol' do
    let(:adder) { described_class.new(context: context) }

    it 'creates OCC-formatted option symbols for calls' do
      symbol = adder.send(:create_option_symbol, 'SPXW', 5900, 'CALL', expiration_date)
      expect(symbol).to eq('SPXW20251017C05900000')
    end

    it 'creates OCC-formatted option symbols for puts' do
      symbol = adder.send(:create_option_symbol, 'SPXW', 5850.5, 'PUT', expiration_date)
      expect(symbol).to eq('SPXW20251017P05850500')
    end

    it 'strips $ and ^ from underlying symbols' do
      symbol = adder.send(:create_option_symbol, '$SPX', 5900, 'CALL', expiration_date)
      expect(symbol).to eq('SPX20251017C05900000')

      symbol = adder.send(:create_option_symbol, '^VIX', 20, 'PUT', expiration_date)
      expect(symbol).to eq('VIX20251017P00020000')
    end
  end

  describe '#generate_target_strikes' do
    let(:adder) { described_class.new(context: context) }

    it 'returns sorted array of strikes' do
      strikes = adder.send(:generate_target_strikes, 5900.0, min_strike: 5800, max_strike: 6000)
      expect(strikes).to eq(strikes.sort)
    end

    it 'includes both min and max strikes' do
      strikes = adder.send(:generate_target_strikes, 5900.0, min_strike: 5800, max_strike: 6000)
      expect(strikes).to include(5800, 6000)
    end

    it 'uses provided min_strike and max_strike when both are present' do
      strikes = adder.send(:generate_target_strikes, 5900.0, min_strike: 5700, max_strike: 6100)
      expect(strikes.min).to eq(5700)
      expect(strikes.max).to eq(6100)
    end

    it 'calculates default min/max using offsets when not provided' do
      strikes = adder.send(:generate_target_strikes, 5900.0)
      # base_strike = 5900
      # min = 5900 + (-3000) = 2900
      # max = 5900 + 1000 = 6900
      expect(strikes.min).to eq(2900)
      expect(strikes.max).to eq(6900)
    end
  end
end
