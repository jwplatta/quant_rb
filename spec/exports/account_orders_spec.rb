require 'spec_helper'
require 'csv'
require 'tempfile'

RSpec.describe OptionsTrader::Exports::AccountOrders do
  let(:schwab_client) { double('SchwabClient') }
  let(:exporter) { described_class.new(schwab_client) }
  let(:from_date) { Date.new(2025, 7, 1) }
  let(:to_date) { Date.new(2025, 7, 19) }
  let(:account_name) { 'test_account' }
  let(:mock_order) do
    double('Order',
      order_id: 'ORDER123',
      filled_quantity: 2,
      order_leg_collection: [mock_order_leg]
    )
  end
  let(:mock_order_leg) do
    double('OrderLeg',
      instrument: mock_instrument,
      quantity: 2,
      position_effect: 'OPENING'
    )
  end
  let(:mock_instrument) do
    double('Instrument',
      instrument_id: 'INST001',
      description: 'SPX Test Option',
      put_call: 'PUT',
      asset_type: 'OPTION'
    )
  end
  let(:mock_transaction) do
    double('Transaction',
      order_id: 'ORDER123',
      trade_date: '2025-07-15T10:30:00Z',
      net_amount: -150.50,
      transfer_items: [mock_transfer_item, mock_fee_item]
    )
  end

  let(:mock_transfer_item) do
    double('TransferItem',
      instrument: mock_instrument,
      cost: -75.25,
      fee_type: nil
    )
  end

  let(:mock_fee_item) do
    double('FeeItem',
      cost: 0.65,
      fee_type: 'COMMISSION'
    )
  end

  before do
    allow(schwab_client).to receive(:account_orders).and_return([mock_order])
    allow(schwab_client).to receive(:transactions).and_return([mock_transaction])

    FileUtils.rm_f(Dir.glob('tmp/account_orders_test_account_*.csv'))
  end

  after do
    FileUtils.rm_f(Dir.glob('tmp/account_orders_test_account_*.csv'))
  end

  describe '#export' do
    it 'creates a CSV file with the correct filename format' do
      filepath = exporter.export(
        from_date: from_date,
        to_date: to_date,
        account_name: account_name
      )

      expect(filepath).to eq('tmp/account_orders_test_account_20250701_20250719.csv')
      expect(File.exist?(filepath)).to be true
    end

    it 'creates CSV with correct headers' do
      filepath = exporter.export(
        from_date: from_date,
        to_date: to_date,
        account_name: account_name
      )

      csv_data = CSV.read(filepath, headers: true)
      expected_headers = [
        'Order ID',
        'Trade Date',
        'Description',
        'Quantity',
        'Put/Call',
        'Position Effect',
        'Cost',
        'Fees & Commissions',
        'Net Amount',
        'Order Net Amount'
      ]

      expect(csv_data.headers).to eq(expected_headers)
    end

    it 'includes order header line with correct format' do
      filepath = exporter.export(
        from_date: from_date,
        to_date: to_date,
        account_name: account_name
      )

      csv_data = CSV.read(filepath, headers: true)
      order_header = csv_data[0]

      expect(order_header['Order ID']).to eq('ORDER123')
      expect(order_header['Description']).to eq('ORDER ORDER123')
      expect(order_header['Trade Date']).to eq('')
      expect(order_header['Quantity']).to eq('')
      expect(order_header['Order Net Amount']).to eq('-150.5')
    end

    it 'includes transaction detail lines with correct data' do
      filepath = exporter.export(
        from_date: from_date,
        to_date: to_date,
        account_name: account_name
      )

      csv_data = CSV.read(filepath, headers: true)
      transaction_line = csv_data[1] # First transaction line after header

      expect(transaction_line['Order ID']).to eq('')
      expect(transaction_line['Trade Date']).to eq('2025-07-15')
      expect(transaction_line['Description']).to eq('SPX Test Option')
      expect(transaction_line['Quantity']).to eq('2')
      expect(transaction_line['Put/Call']).to eq('PUT')
      expect(transaction_line['Position Effect']).to eq('OPENING')
      expect(transaction_line['Cost']).to eq('-75.25')
      expect(transaction_line['Fees & Commissions']).to eq('0.65')
      expect(transaction_line['Net Amount']).to eq('-150.5')
      expect(transaction_line['Order Net Amount']).to eq('')
    end

    it 'includes order summary line with totals' do
      filepath = exporter.export(
        from_date: from_date,
        to_date: to_date,
        account_name: account_name
      )

      csv_data = CSV.read(filepath, headers: true)
      summary_line = csv_data[2] # Summary line after transaction

      expect(summary_line['Order ID']).to eq('')
      expect(summary_line['Description']).to eq('ORDER ORDER123 SUMMARY')
      expect(summary_line['Quantity']).to eq('2')
      expect(summary_line['Cost']).to eq('-75.25')
      expect(summary_line['Fees & Commissions']).to eq('0.65')
      expect(summary_line['Net Amount']).to eq('-150.5')
    end

    it 'includes export summary at the bottom' do
      filepath = exporter.export(
        from_date: from_date,
        to_date: to_date,
        account_name: account_name
      )

      csv_data = CSV.read(filepath, headers: true)
      export_summary = csv_data.to_a.last

      expect(export_summary[2]).to eq('EXPORT SUMMARY')
      expect(export_summary[8]).to eq('-150.5')
    end

    it 'includes blank lines for separation' do
      filepath = exporter.export(
        from_date: from_date,
        to_date: to_date,
        account_name: account_name
      )

      csv_data = CSV.read(filepath, headers: true)
      blank_line_after_order = csv_data[3]
      blank_line_before_export_summary = csv_data[4]

      expect(blank_line_after_order.fields.all?(&:empty?)).to be true
      expect(blank_line_before_export_summary.fields.all?(&:empty?)).to be true
    end

    it 'creates tmp directory if it does not exist' do
      FileUtils.rm_rf('tmp')
      expect(Dir.exist?('tmp')).to be false

      exporter.export(
        from_date: from_date,
        to_date: to_date,
        account_name: account_name
      )

      expect(Dir.exist?('tmp')).to be true
    end
  end
end
