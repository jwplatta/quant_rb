require 'rspec'
require 'pry'
require 'json'
require_relative '../../../mixins/schwab/schwab'
require_relative '../../../mixins/schwab/data_objects/quote'
require_relative '../../../mixins/schwab/data_objects/option_chain'
require_relative '../../../mixins/schwab/data_objects/account'
require_relative '../../../mixins/schwab/data_objects/transaction'
require_relative '../../../mixins/schwab/data_objects/order'
require_relative '../../../mixins/schwab/data_objects/order_preview'
require_relative '../../../mixins/schwab/orders/order_factory'

RSpec.describe Schwab do
  # Create a test class that includes the Schwab mixin
  let(:test_class) do
    Class.new do
      include Schwab
    end
  end

  let(:schwab_instance) { test_class.new }

  # Mock the SchwabRb client
  let(:mock_client) { double('SchwabRb::Client') }

  before do
    # Stub the client method to return our mock client
    allow(schwab_instance).to receive(:client).and_return(mock_client)
    allow(schwab_instance).to receive(:account_hash).and_return('ABC123XYZ')
  end

  describe '#quote' do
    let(:quote_response) do
      instance_double('Response', body: File.read('spec/fixtures/quotes/NVDA_quote.json'))
    end

    it 'fetches and returns a quote for a symbol' do
      expect(mock_client).to receive(:get_quote).with('NVDA').and_return(quote_response)

      quote = schwab_instance.quote('NVDA')
      expect(quote).to be_an_instance_of(DataObjects::EquityQuote)
      expect(quote.symbol).to eq('NVDA')
    end
  end

  describe '#quotes' do
    let(:quotes_response) do
      quotes_data = {
        'NVDA' => JSON.parse(File.read('spec/fixtures/quotes/NVDA_quote.json'))['NVDA'],
        '$SPX' => JSON.parse(File.read('spec/fixtures/quotes/$SPX_quote.json'))['$SPX']
      }
      instance_double('Response', body: quotes_data.to_json)
    end

    it 'fetches and returns quotes for multiple symbols' do
      expect(mock_client).to receive(:get_quotes).with(['NVDA', '$SPX']).and_return(quotes_response)

      quotes = schwab_instance.quotes(['NVDA', '$SPX'])
      expect(quotes).to be_an_instance_of(Array)
      expect(quotes.size).to eq(2)

      expect(quotes.map(&:class)).to include(DataObjects::EquityQuote, DataObjects::IndexQuote)
      expect(quotes.map(&:symbol).sort).to eq(['$SPX', 'NVDA'].sort)
    end
  end

  describe '#option_chain' do
    let(:option_chain_response) do
      instance_double('Response',
        body: File.read('spec/fixtures/option_chains/ACME_calls.json')
      )
    end

    it 'fetches and returns an option chain for a symbol' do
      expect(mock_client).to receive(:get_option_chain)
        .with('ACME', contract_type: 'CALL', strike_range: 'OTM', to_date: Date.today + 30)
        .and_return(option_chain_response)

      chain = schwab_instance.option_chain('ACME',
        contract_type: 'CALL',
        strike_range: 'OTM',
        to_date: Date.today + 30
      )

      expect(chain).to be_an_instance_of(DataObjects::OptionChain)
    end

    it 'uses days_to_expiration when provided' do
      expect(mock_client).to receive(:get_option_chain)
        .with('ACME', contract_type: 'CALL', strike_range: 'OTM', days_to_expiration: 30)
        .and_return(option_chain_response)

      chain = schwab_instance.option_chain('ACME',
        contract_type: 'CALL',
        strike_range: 'OTM',
        days_to_expiration: 30
      )

      expect(chain).to be_an_instance_of(DataObjects::OptionChain)
    end
  end

  describe '#account' do
    let(:account_response) do
      instance_double('Response',
        body: File.read('spec/fixtures/account.json')
      )
    end

    it 'fetches and returns account information' do
      expect(mock_client).to receive(:get_account)
        .with('ABC123XYZ', fields: nil)
        .and_return(account_response)

      account = schwab_instance.account
      expect(account).to be_an_instance_of(DataObjects::Account)
      expect(account.account_number).to eq('11111111')
    end

    it 'accepts optional fields parameter' do
      expect(mock_client).to receive(:get_account)
        .with('ABC123XYZ', fields: 'positions,orders')
        .and_return(account_response)

      account = schwab_instance.account(fields: 'positions,orders')
      expect(account).to be_an_instance_of(DataObjects::Account)
    end
  end

  describe '#transactions' do
    let(:transactions_response) do
      instance_double('Response',
        body: File.read('spec/fixtures/transactions.json')
      )
    end

    it 'fetches and returns transactions' do
      # Allow specific method call with empty hash
      expect(mock_client).to receive(:get_transactions)
        .with('ABC123XYZ')
        .and_return(transactions_response)

      transactions = schwab_instance.transactions
      expect(transactions).to be_an_instance_of(Array)
      expect(transactions.size).to eq(2)
      expect(transactions.first).to be_an_instance_of(DataObjects::Transaction)
      expect(transactions.first.type).to eq("TRADE")
      expect(transactions.first.order_id).to eq("1002613435352")

      # Verify the transfer items
      expect(transactions.first.transfer_items).to be_an_instance_of(Array)
      expect(transactions.first.transfer_items.first.instrument.symbol).to eq("MRVL  250321C00155000")
    end

    it 'accepts optional parameters' do
      start_date = Date.new(2025, 1, 1)
      end_date = Date.new(2025, 1, 31)

      expect(mock_client).to receive(:get_transactions)
        .with('ABC123XYZ', {
          start_date: start_date,
          end_date: end_date,
          transaction_types: 'TRADE',
          symbol: 'MRVL'
        })
        .and_return(transactions_response)

      transactions = schwab_instance.transactions(
        start_date: start_date,
        end_date: end_date,
        transaction_types: 'TRADE',
        symbol: 'MRVL'
      )

      expect(transactions).to be_an_instance_of(Array)
      expect(transactions.first).to be_an_instance_of(DataObjects::Transaction)

      # Verify that transfer items are processed correctly
      expect(transactions.first.transfer_items.size).to be > 0

      # Check if fees are extracted correctly
      fee_items = transactions.first.transfer_items.select { |item| item.fee_type }
      expect(fee_items).not_to be_empty
    end
  end

  describe '#account_orders' do
    let(:orders_response) do
      instance_double('Response',
        body: File.read('spec/fixtures/orders.json')
      )
    end

    it 'fetches and returns orders for the account' do
      from_date = Date.new(2025, 1, 1)
      to_date = Date.new(2025, 1, 31)
      status = 'FILLED'

      expect(mock_client).to receive(:get_account_orders)
        .with('ABC123XYZ', from_entered_datetime: from_date, to_entered_datetime: to_date, status: status)
        .and_return(orders_response)

      orders = schwab_instance.account_orders(from_date, to_date, status)
      expect(orders).to be_an_instance_of(Array)
      expect(orders.first).to be_an_instance_of(DataObjects::Order)
      expect(orders.first.status).to eq('FILLED')
    end
  end

  describe '#preview_order' do
    let(:preview_response) do
      instance_double('Response',
        body: File.read('spec/fixtures/order_preview.json')
      )
    end

    it 'previews an order and returns an order preview' do
      order_data = {
        orderType: 'NET_CREDIT',
        session: 'NORMAL',
        duration: 'DAY',
        orderStrategyType: 'SINGLE',
        price: 1.25,
        orderLegs: [
          {
            instrument: {
              symbol: "SPX  250317P04350000"
            },
            instruction: "SELL_TO_OPEN",
            quantity: 1
          },
          {
            instrument: {
              symbol: "SPX  250317P04250000"
            },
            instruction: "BUY_TO_OPEN",
            quantity: 1
          }
        ]
      }

      expect(mock_client).to receive(:preview_order)
        .with('ABC123XYZ', order_data)
        .and_return(preview_response)

      preview = schwab_instance.preview_order(order_data)
      expect(preview).to be_an_instance_of(DataObjects::OrderPreview)
      expect(preview.accepted?).to be true
      expect(preview.commission).to eq(1.3) # 0.65 * 2
      expect(preview.fees).to eq(1.14) # 0.01*2 + 0.56*2
    end
  end

  describe '#get_order' do
    let(:order_response) do
      # Extract the first order from the array as a hash
      order_data = JSON.parse(File.read('spec/fixtures/orders.json'), symbolize_names: true).first
      instance_double('Response', body: order_data.to_json)
    end

    it 'fetches a specific order by ID' do
      order_id = "1002613435352"

      expect(mock_client).to receive(:get_order)
        .with(order_id, 'ABC123XYZ')
        .and_return(order_response)

      order = schwab_instance.get_order(order_id)
      expect(order).to be_an_instance_of(DataObjects::Order)
      expect(order.order_id.to_s).to eq("1002613435352")
    end
  end

  describe '#cancel_order' do
    let(:cancel_response) do
      instance_double('Response', status: 200)
    end

    it 'cancels an order and returns success status' do
      order_id = 1002613435352

      expect(mock_client).to receive(:cancel_order)
        .with(order_id, 'ABC123XYZ')
        .and_return(cancel_response)

      result = schwab_instance.cancel_order(order_id)
      expect(result).to be true
    end
  end
end