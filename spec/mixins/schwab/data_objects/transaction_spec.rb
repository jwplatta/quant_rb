require 'rspec'
require 'json'
require_relative '../../../../mixins/schwab/data_objects/transaction'

RSpec.describe DataObjects::Transaction do
  let(:transaction_data) do
    JSON.parse(File.read('spec/fixtures/transaction_single.json'), symbolize_names: true)
  end

  describe '.build' do
    it 'creates a transaction object from raw data' do
      transaction = DataObjects::Transaction.build(transaction_data)

      expect(transaction).to be_an_instance_of(DataObjects::Transaction)
      expect(transaction.activity_id).to eq(91176753938)
      expect(transaction.time).to eq("2025-01-17T17:19:49+0000")
      expect(transaction.type).to eq("TRADE")
      expect(transaction.status).to eq("VALID")
      expect(transaction.sub_account).to eq("CASH")
      expect(transaction.trade_date).to eq("2025-01-17")
      expect(transaction.position_id).to eq(12345678)
      expect(transaction.order_id).to eq("1002613435352")
      expect(transaction.net_amount).to eq(-1215.95)
      expect(transaction.trade?).to be true

      # Test transfer items
      expect(transaction.transfer_items).to be_an_instance_of(Array)
      expect(transaction.transfer_items.size).to eq(2)
      expect(transaction.transfer_items.first).to be_an_instance_of(DataObjects::TransferItem)

      # Test the option transfer item
      option_item = transaction.transfer_items.first
      expect(option_item.amount).to eq(-1.0)
      expect(option_item.cost).to eq(206.0)
      expect(option_item.position_effect).to eq("OPENING")
      expect(option_item.instrument).to be_an_instance_of(DataObjects::Instrument)
      expect(option_item.instrument.symbol).to eq("MRVL  250321C00155000")
      expect(option_item.instrument.asset_type).to eq("OPTION")
      expect(option_item.option?).to be true

      # Test the fee transfer item
      fee_item = transaction.transfer_items.last
      expect(fee_item.amount).to eq(0.95)
      expect(fee_item.cost).to eq(-0.95)
      expect(fee_item.fee_type).to eq("OPT_REG_FEE")
      expect(fee_item.fee?).to be true

      # Test transaction helpers
      expect(transaction.symbols).to include("MRVL  250321C00155000")
      expect(transaction.option_symbol).to eq("MRVL  250321C00155000")
    end
  end
end

RSpec.describe DataObjects::TransferItem do
  let(:transfer_item_data) do
    {
      amount: 1.0,
      cost: 86.0,
      positionEffect: "OPENING",
      instrument: {
        assetType: "OPTION",
        cusip: "0MRVL.CL50170000",
        symbol: "MRVL  250321C00170000",
        description: "MARVELL TECHNOLOGY INC 03/21/2025 $170 Call",
        putCall: "CALL",
        underlyingSymbol: "MRVL"
      }
    }
  end

  describe '.build' do
    it 'creates a transfer item from raw data' do
      transfer_item = DataObjects::TransferItem.build(transfer_item_data)

      expect(transfer_item).to be_an_instance_of(DataObjects::TransferItem)
      expect(transfer_item.amount).to eq(1.0)
      expect(transfer_item.cost).to eq(86.0)
      expect(transfer_item.position_effect).to eq("OPENING")
      expect(transfer_item.fee_type).to be_nil

      # Check instrument data
      expect(transfer_item.instrument).to be_an_instance_of(DataObjects::Instrument)
      expect(transfer_item.instrument.symbol).to eq("MRVL  250321C00170000")
      expect(transfer_item.instrument.description).to eq("MARVELL TECHNOLOGY INC 03/21/2025 $170 Call")
      expect(transfer_item.instrument.cusip).to eq("0MRVL.CL50170000")
      expect(transfer_item.instrument.asset_type).to eq("OPTION")
      expect(transfer_item.instrument.put_call).to eq("CALL")
      expect(transfer_item.instrument.underlying_symbol).to eq("MRVL")

      # Test helper methods
      expect(transfer_item.option?).to be true
      expect(transfer_item.symbol).to eq("MRVL  250321C00170000")
      expect(transfer_item.underlying_symbol).to eq("MRVL")
      expect(transfer_item.description).to eq("MARVELL TECHNOLOGY INC 03/21/2025 $170 Call")
      expect(transfer_item.put_call).to eq("CALL")
      expect(transfer_item.fee?).to be false
      expect(transfer_item.commission?).to be false
    end

    it 'correctly identifies fee transfer items' do
      fee_data = transfer_item_data.merge(feeType: "OPT_REG_FEE")
      fee_item = DataObjects::TransferItem.build(fee_data)

      expect(fee_item.fee?).to be true
      expect(fee_item.commission?).to be false
    end

    it 'correctly identifies commission transfer items' do
      commission_data = transfer_item_data.merge(feeType: "COMMISSION")
      commission_item = DataObjects::TransferItem.build(commission_data)

      expect(commission_item.fee?).to be false
      expect(commission_item.commission?).to be true
    end
  end
end
