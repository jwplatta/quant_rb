require 'spec_helper'

RSpec.xdescribe OptionsTrader::Services::DeltaEnricher do
  let(:predictor) { instance_double(OptionsTrader::Predictors::GreekForge) }
  let(:enricher) { described_class.new(predictor: predictor) }

  describe '#enrich' do
    let(:underlying_price) { 6000.0 }

    let(:call_opts) do
      [
        create_option(strike: 5900.0, put_call: 'CALL', underlying_price: underlying_price),
        create_option(strike: 6000.0, put_call: 'CALL', underlying_price: underlying_price),
        create_option(strike: 6100.0, put_call: 'CALL', underlying_price: underlying_price)
      ]
    end

    let(:put_opts) do
      [
        create_option(strike: 5900.0, put_call: 'PUT', underlying_price: underlying_price),
        create_option(strike: 6000.0, put_call: 'PUT', underlying_price: underlying_price),
        create_option(strike: 6100.0, put_call: 'PUT', underlying_price: underlying_price)
      ]
    end

    let(:option_chain) do
      OptionsTrader::DataObjects::OptionsChain.new(
        symbol: 'SPXW',
        underlying_price: underlying_price,
        call_opts: call_opts,
        put_opts: put_opts
      )
    end

    let(:call_predictions) do
      {
        'predictions' => [0.65, 0.50, 0.35],
        'contract_type' => 'CALL',
        'model_version' => '1.0.0',
        'count' => 3
      }
    end

    let(:put_predictions) do
      {
        'predictions' => [-0.35, -0.50, -0.65],
        'contract_type' => 'PUT',
        'model_version' => '1.0.0',
        'count' => 3
      }
    end

    before do
      allow(predictor).to receive(:predict_deltas).and_return(call_predictions, put_predictions)
    end

    it 'enriches option chain with predicted deltas' do
      result = enricher.enrich(option_chain)

      expect(result).to eq(option_chain)
      expect(call_opts[0].delta).to be_within(0.01).of(0.65)
      expect(call_opts[1].delta).to be_within(0.01).of(0.50)
      expect(call_opts[2].delta).to be_within(0.01).of(0.35)
    end

    it 'calls predictor for both calls and puts' do
      enricher.enrich(option_chain)

      expect(predictor).to have_received(:predict_deltas).twice
    end

    context 'when calls are empty' do
      let(:call_opts) { [] }

      before do
        allow(predictor).to receive(:predict_deltas).and_return(put_predictions)
      end

      it 'only predicts for puts' do
        enricher.enrich(option_chain)

        expect(predictor).to have_received(:predict_deltas).once
      end
    end

    context 'when puts are empty' do
      let(:put_opts) { [] }

      before do
        allow(predictor).to receive(:predict_deltas).and_return(call_predictions)
      end

      it 'only predicts for calls' do
        enricher.enrich(option_chain)

        expect(predictor).to have_received(:predict_deltas).once
      end
    end
  end

  describe '#enrich_batch' do
    let(:chain1) do
      OptionsTrader::DataObjects::OptionsChain.new(
        symbol: 'SPXW1',
        underlying_price: 6000.0,
        call_opts: [create_option(strike: 6000.0, put_call: 'CALL', underlying_price: 6000.0)],
        put_opts: [create_option(strike: 6000.0, put_call: 'PUT', underlying_price: 6000.0)]
      )
    end

    let(:chain2) do
      OptionsTrader::DataObjects::OptionsChain.new(
        symbol: 'SPXW2',
        underlying_price: 6100.0,
        call_opts: [create_option(strike: 6100.0, put_call: 'CALL', underlying_price: 6100.0)],
        put_opts: [create_option(strike: 6100.0, put_call: 'PUT', underlying_price: 6100.0)]
      )
    end

    let(:predictions) do
      {
        'predictions' => [0.50],
        'contract_type' => 'CALL',
        'model_version' => '1.0.0',
        'count' => 1
      }
    end

    before do
      allow(predictor).to receive(:predict_deltas).and_return(predictions)
    end

    it 'enriches multiple option chains' do
      result = enricher.enrich_batch([chain1, chain2])

      expect(result).to eq([chain1, chain2])
      expect(result.size).to eq(2)
    end
  end

  describe '#validate_required_features' do
    context 'when all features are present' do
      let(:options) do
        [create_option(strike: 6000.0, put_call: 'CALL', underlying_price: 6000.0)]
      end

      it 'does not raise an error' do
        expect {
          enricher.send(:validate_required_features, options, 'CALL')
        }.not_to raise_error
      end
    end

    context 'when days_to_expiration is missing' do
      let(:options) do
        [create_option(strike: 6000.0, put_call: 'CALL', underlying_price: 6000.0, days_to_expiration: nil)]
      end

      it 'raises an error' do
        expect {
          enricher.send(:validate_required_features, options, 'CALL')
        }.to raise_error(OptionsTrader::Services::DeltaEnricher::Error, /days_to_expiration missing/)
      end
    end

    context 'when underlying_price is zero (causing moneyness calculation to fail)' do
      let(:options) do
        [create_option(strike: 6000.0, put_call: 'CALL', underlying_price: 0.0)]
      end

      it 'raises an error for invalid underlying_price' do
        expect {
          enricher.send(:validate_required_features, options, 'CALL')
        }.to raise_error(OptionsTrader::Services::DeltaEnricher::Error, /underlying_price missing or invalid/)
      end
    end

    context 'when mark is missing' do
      let(:options) do
        [create_option(strike: 6000.0, put_call: 'CALL', underlying_price: 6000.0, mark: nil)]
      end

      it 'raises an error' do
        expect {
          enricher.send(:validate_required_features, options, 'CALL')
        }.to raise_error(OptionsTrader::Services::DeltaEnricher::Error, /mark missing/)
      end
    end

    context 'when vix9d is missing' do
      let(:options) do
        [create_option(strike: 6000.0, put_call: 'CALL', underlying_price: 6000.0, vix9d: nil)]
      end

      it 'raises an error' do
        expect {
          enricher.send(:validate_required_features, options, 'CALL')
        }.to raise_error(OptionsTrader::Services::DeltaEnricher::Error, /vix9d missing/)
      end
    end

    context 'when vvix is missing' do
      let(:options) do
        [create_option(strike: 6000.0, put_call: 'CALL', underlying_price: 6000.0, vvix: nil)]
      end

      it 'raises an error' do
        expect {
          enricher.send(:validate_required_features, options, 'CALL')
        }.to raise_error(OptionsTrader::Services::DeltaEnricher::Error, /vvix missing/)
      end
    end
  end

  describe '#enforce_parity' do
    let(:underlying_price) { 6000.0 }

    let(:call_opts) do
      [
        create_option(strike: 5900.0, put_call: 'CALL', underlying_price: underlying_price, delta: 0.65),
        create_option(strike: 6000.0, put_call: 'CALL', underlying_price: underlying_price, delta: 0.50),
        create_option(strike: 6100.0, put_call: 'CALL', underlying_price: underlying_price, delta: 0.35)
      ]
    end

    let(:put_opts) do
      [
        create_option(strike: 5900.0, put_call: 'PUT', underlying_price: underlying_price, delta: -0.35),
        create_option(strike: 6000.0, put_call: 'PUT', underlying_price: underlying_price, delta: -0.50),
        create_option(strike: 6100.0, put_call: 'PUT', underlying_price: underlying_price, delta: -0.65)
      ]
    end

    it 'enforces put-call parity for ITM calls' do
      enricher.send(:enforce_parity, call_opts, put_opts, underlying_price)

      # ITM call (5900) should use PUT delta to calculate CALL delta
      # delta_call = delta_put + 1.0
      expect(call_opts[0].delta).to eq(-0.35 + 1.0) # 0.65
    end

    it 'enforces put-call parity for ITM puts' do
      enricher.send(:enforce_parity, call_opts, put_opts, underlying_price)

      # ITM put (6100) should use CALL delta to calculate PUT delta
      # delta_put = delta_call - 1.0
      expect(put_opts[2].delta).to eq(0.35 - 1.0) # -0.65
    end

    it 'averages ATM deltas' do
      enricher.send(:enforce_parity, call_opts, put_opts, underlying_price)

      # ATM (6000) should average the predictions
      avg_abs_delta = (0.50.abs + 0.50.abs) / 2.0
      expect(call_opts[1].delta).to eq(avg_abs_delta)
      expect(put_opts[1].delta).to eq(-avg_abs_delta)
    end

    context 'when calls are empty' do
      let(:call_opts) { [] }

      it 'does not raise an error' do
        expect {
          enricher.send(:enforce_parity, call_opts, put_opts, underlying_price)
        }.not_to raise_error
      end
    end

    context 'when puts are empty' do
      let(:put_opts) { [] }

      it 'does not raise an error' do
        expect {
          enricher.send(:enforce_parity, call_opts, put_opts, underlying_price)
        }.not_to raise_error
      end
    end
  end

  def create_option(
    strike:,
    put_call:,
    underlying_price:,
    days_to_expiration: 5,
    mark: 10.5,
    vix9d: 15.0,
    vvix: 90.0,
    skew: 140.0,
    moneyness: 1.0,
    delta: nil
  )
    # Create a real Option object so we can use the dynamic feature system
    option = OptionsTrader::DataObjects::Option.new(
      symbol: "TEST#{strike}#{put_call[0]}",
      underlying_symbol: '$SPX',
      strike: strike,
      put_call: put_call,
      mark: mark,
      underlying_price: underlying_price,
      expiration_date: '2025-12-31',
      days_to_expiration: days_to_expiration,
      delta: delta
    )

    # Set dynamic features using the new set_feature method
    option.set_feature(:vix9d, vix9d) if vix9d
    option.set_feature(:vvix, vvix) if vvix
    option.set_feature(:skew, skew) if skew
    option.set_feature(:moneyness, moneyness) if moneyness

    option
  end
end
