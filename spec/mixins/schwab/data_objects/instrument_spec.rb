require 'rspec'
require 'json'
require_relative '../../../../mixins/schwab/data_objects/instrument'

RSpec.describe DataObjects::Instrument do
  let(:option_instrument_data) do
    JSON.parse(File.read('spec/fixtures/instrument.json'), symbolize_names: true)
  end

  let(:equity_instrument_data) do
    JSON.parse(File.read('spec/fixtures/equity_instrument.json'), symbolize_names: true)
  end

  describe '.build' do
    it 'creates an option instrument object from raw data' do
      instrument = DataObjects::Instrument.build(option_instrument_data)

      expect(instrument).to be_an_instance_of(DataObjects::Instrument)
      expect(instrument.asset_type).to eq('OPTION')
      expect(instrument.symbol).to eq('TSLA  250221P00340000')
      expect(instrument.description).to eq('TESLA INC 02/21/2025 $340 Put')
      expect(instrument.cusip).to eq('0TSLA.NL50340000')
      expect(instrument.net_change).to eq(-0.525)
      expect(instrument.type).to eq('VANILLA')
      expect(instrument.put_call).to eq('PUT')
      expect(instrument.underlying_symbol).to eq('TSLA')
      expect(instrument.status).to eq('NORMAL')
      expect(instrument.instrument_id).to eq(221175400)
      expect(instrument.closing_price).to eq(6.45)
      expect(instrument.option?).to be true

      expect(instrument.option_deliverables).to be_an_instance_of(Array)
      expect(instrument.option_deliverables.length).to eq(1)
      expect(instrument.option_deliverables.first).to be_an_instance_of(DataObjects::OptionDeliverable)
      expect(instrument.option_deliverables.first.symbol).to eq('TSLA')
      expect(instrument.option_deliverables.first.deliverable_units).to eq(100.0)
    end

    it 'creates an equity instrument object from raw data' do
      instrument = DataObjects::Instrument.build(equity_instrument_data)

      expect(instrument).to be_an_instance_of(DataObjects::Instrument)
      expect(instrument.asset_type).to eq('EQUITY')
      expect(instrument.symbol).to eq('TSLA')
      expect(instrument.description).to eq('TESLA INC')
      expect(instrument.cusip).to eq('88160R101')
      expect(instrument.net_change).to eq(2.56)
      expect(instrument.status).to eq('NORMAL')
      expect(instrument.instrument_id).to eq(11181301)
      expect(instrument.closing_price).to eq(248.33)
      expect(instrument.option?).to be false
      expect(instrument.option_deliverables).to be_empty
    end
  end

  describe '#to_h' do
    it 'converts the option instrument object back to a hash with the same structure as the input data' do
      instrument = DataObjects::Instrument.build(option_instrument_data)
      instrument_hash = instrument.to_h

      expect(instrument_hash[:assetType]).to eq(option_instrument_data[:assetType])
      expect(instrument_hash[:symbol]).to eq(option_instrument_data[:symbol])
      expect(instrument_hash[:description]).to eq(option_instrument_data[:description])
      expect(instrument_hash[:cusip]).to eq(option_instrument_data[:cusip])
      expect(instrument_hash[:netChange]).to eq(option_instrument_data[:netChange])
      expect(instrument_hash[:type]).to eq(option_instrument_data[:type])
      expect(instrument_hash[:putCall]).to eq(option_instrument_data[:putCall])
      expect(instrument_hash[:underlyingSymbol]).to eq(option_instrument_data[:underlyingSymbol])
      expect(instrument_hash[:status]).to eq(option_instrument_data[:status])
      expect(instrument_hash[:instrumentId]).to eq(option_instrument_data[:instrumentId])
      expect(instrument_hash[:closingPrice]).to eq(option_instrument_data[:closingPrice])

      # Verify option deliverables
      expect(instrument_hash[:optionDeliverables].length).to eq(option_instrument_data[:optionDeliverables].length)
      expect(instrument_hash[:optionDeliverables][0][:symbol]).to eq(option_instrument_data[:optionDeliverables][0][:symbol])
    end

    it 'converts the equity instrument object back to a hash with the same structure as the input data' do
      instrument = DataObjects::Instrument.build(equity_instrument_data)
      instrument_hash = instrument.to_h

      expect(instrument_hash[:assetType]).to eq(equity_instrument_data[:assetType])
      expect(instrument_hash[:symbol]).to eq(equity_instrument_data[:symbol])
      expect(instrument_hash[:description]).to eq(equity_instrument_data[:description])
      expect(instrument_hash[:cusip]).to eq(equity_instrument_data[:cusip])
      expect(instrument_hash[:netChange]).to eq(equity_instrument_data[:netChange])
      expect(instrument_hash[:status]).to eq(equity_instrument_data[:status])
      expect(instrument_hash[:instrumentId]).to eq(equity_instrument_data[:instrumentId])
      expect(instrument_hash[:closingPrice]).to eq(equity_instrument_data[:closingPrice])

      # Verify empty option deliverables array
      expect(instrument_hash[:optionDeliverables]).to be_empty
    end
  end
end

RSpec.describe DataObjects::OptionDeliverable do
  let(:option_deliverable_data) do
    {
      symbol: 'TSLA',
      deliverableUnits: 100.0,
      deliverableNumber: 1,
      strikePercent: 1.0,
      rootSymbol: 'TSLA'
    }
  end

  describe '.build' do
    it 'creates an option deliverable object from raw data' do
      deliverable = DataObjects::OptionDeliverable.build(option_deliverable_data)

      expect(deliverable).to be_an_instance_of(DataObjects::OptionDeliverable)
      expect(deliverable.symbol).to eq('TSLA')
      expect(deliverable.deliverable_units).to eq(100.0)
      expect(deliverable.deliverable_number).to eq(1)
      expect(deliverable.strike_percent).to eq(1.0)
      expect(deliverable.root_symbol).to eq('TSLA')
      expect(deliverable.deliverable).to be_nil
    end
  end

  describe '#to_h' do
    it 'converts the option deliverable object back to a hash with the same structure as the input data' do
      deliverable = DataObjects::OptionDeliverable.build(option_deliverable_data)
      deliverable_hash = deliverable.to_h

      expect(deliverable_hash[:symbol]).to eq(option_deliverable_data[:symbol])
      expect(deliverable_hash[:deliverableUnits]).to eq(option_deliverable_data[:deliverableUnits])
      expect(deliverable_hash[:deliverableNumber]).to eq(option_deliverable_data[:deliverableNumber])
      expect(deliverable_hash[:strikePercent]).to eq(option_deliverable_data[:strikePercent])
      expect(deliverable_hash[:rootSymbol]).to eq(option_deliverable_data[:rootSymbol])
      expect(deliverable_hash[:deliverable]).to be_nil
    end
  end
end

RSpec.describe DataObjects::Asset do
  let(:asset_data) do
    {
      assetType: 'FUTURE',
      status: 'ACTIVE',
      symbol: 'ESZ3',
      instrumentId: 12345678,
      closingPrice: 4350.25,
      type: 'FUTURE',
      description: 'E-mini S&P 500 Future December 2023',
      activeContract: true,
      expirationDate: '2023-12-15',
      lastTradingDate: '2023-12-14',
      multiplier: 50.0,
      futureType: 'EMINI'
    }
  end

  describe '.build' do
    it 'creates an asset object from raw data' do
      asset = DataObjects::Asset.build(asset_data)

      expect(asset).to be_an_instance_of(DataObjects::Asset)
      expect(asset.asset_type).to eq('FUTURE')
      expect(asset.status).to eq('ACTIVE')
      expect(asset.symbol).to eq('ESZ3')
      expect(asset.instrument_id).to eq(12345678)
      expect(asset.closing_price).to eq(4350.25)
      expect(asset.type).to eq('FUTURE')
      expect(asset.description).to eq('E-mini S&P 500 Future December 2023')
      expect(asset.active_contract).to be true
      expect(asset.expiration_date).to eq('2023-12-15')
      expect(asset.last_trading_date).to eq('2023-12-14')
      expect(asset.multiplier).to eq(50.0)
      expect(asset.future_type).to eq('EMINI')
    end
  end

  describe '#to_h' do
    it 'converts the asset object back to a hash with the same structure as the input data' do
      asset = DataObjects::Asset.build(asset_data)
      asset_hash = asset.to_h

      expect(asset_hash[:assetType]).to eq(asset_data[:assetType])
      expect(asset_hash[:status]).to eq(asset_data[:status])
      expect(asset_hash[:symbol]).to eq(asset_data[:symbol])
      expect(asset_hash[:instrumentId]).to eq(asset_data[:instrumentId])
      expect(asset_hash[:closingPrice]).to eq(asset_data[:closingPrice])
      expect(asset_hash[:type]).to eq(asset_data[:type])
      expect(asset_hash[:description]).to eq(asset_data[:description])
      expect(asset_hash[:activeContract]).to eq(asset_data[:activeContract])
      expect(asset_hash[:expirationDate]).to eq(asset_data[:expirationDate])
      expect(asset_hash[:lastTradingDate]).to eq(asset_data[:lastTradingDate])
      expect(asset_hash[:multiplier]).to eq(asset_data[:multiplier])
      expect(asset_hash[:futureType]).to eq(asset_data[:futureType])
    end
  end
end