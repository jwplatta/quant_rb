# frozen_string_literal: true

RSpec.describe Platypi::Schwab do
  # Create a test class that includes the Platypi::Schwab module
  let(:test_class) do
    Class.new do
      include Platypi::Schwab
    end
  end

  let(:schwab_instance) { test_class.new }

  # Mock the SchwabRb client
  let(:mock_client) { double('SchwabRb::Client') }

  before do
    # Stub the client method to return our mock client
    allow(schwab_instance).to receive(:client).and_return(mock_client)
    allow(schwab_instance).to receive(:account_hash).and_return('ABC123XYZ')

    # Clear the cache before each test
    test_class.clear_option_chain_cache if test_class.respond_to?(:clear_option_chain_cache)
  end

  describe '#quote' do
    let(:quote_response) do
      instance_double('Response', body: File.read('spec/fixtures/quotes/NVDA_quote.json'))
    end

    it 'fetches and returns a quote for a symbol' do
      expect(mock_client).to receive(:get_quote).with('NVDA').and_return(quote_response)

      quote = schwab_instance.quote('NVDA')
      expect(quote).to be_an_instance_of(Platypi::Schwab::DataObjects::EquityQuote)
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

      expect(quotes.map(&:class)).to include(Platypi::Schwab::DataObjects::EquityQuote, Platypi::Schwab::DataObjects::IndexQuote)
      expect(quotes.map(&:symbol).sort).to eq(['$SPX', 'NVDA'].sort)
    end
  end

  describe '#option_chain' do
    let(:option_chain_response) do
      instance_double('Response', body: File.read("spec/fixtures/option_chains/ACME_calls.json"))
    end

    it 'fetches and returns an option chain for a symbol' do
      expect(mock_client).to receive(:get_option_chain)
        .with('ACME', {contract_type: 'CALL', strike_range: 'OTM', to_date: Date.today + 30})
        .and_return(option_chain_response)

      chain = schwab_instance.option_chain('ACME',
                                         contract_type: 'CALL',
                                         strike_range: 'OTM',
                                         to_date: Date.today + 30)

      expect(chain).to be_an_instance_of(Platypi::Schwab::DataObjects::OptionChain)
    end

    it 'uses days_to_expiration when provided' do
      expect(mock_client).to receive(:get_option_chain)
        .with('ACME', {contract_type: 'CALL', strike_range: 'OTM', days_to_expiration: 30})
        .and_return(option_chain_response)

      chain = schwab_instance.option_chain('ACME',
                                         contract_type: 'CALL',
                                         strike_range: 'OTM',
                                         days_to_expiration: 30)

      expect(chain).to be_an_instance_of(Platypi::Schwab::DataObjects::OptionChain)
    end

    it 'does not cache results between calls' do
      expect(mock_client).to receive(:get_option_chain)
        .twice
        .with('ACME', {contract_type: 'CALL', strike_range: 'OTM', to_date: nil})
        .and_return(option_chain_response)

      # First call
      chain1 = schwab_instance.option_chain('ACME',
                                          contract_type: 'CALL',
                                          strike_range: 'OTM')

      # Second call with same params should not use cache
      chain2 = schwab_instance.option_chain('ACME',
                                          contract_type: 'CALL',
                                          strike_range: 'OTM')

      # Both should be option chains but they should be separate instances
      expect(chain1).to be_an_instance_of(Platypi::Schwab::DataObjects::OptionChain)
      expect(chain2).to be_an_instance_of(Platypi::Schwab::DataObjects::OptionChain)
    end

    it 'does not use caching at all' do
      expect(mock_client).to receive(:get_option_chain)
        .twice
        .with('ACME', {contract_type: 'CALL', strike_range: 'OTM', to_date: nil})
        .and_return(option_chain_response)

      # First call
      chain1 = schwab_instance.option_chain('ACME',
                                          contract_type: 'CALL',
                                          strike_range: 'OTM')

      # Second call should hit the API again
      chain2 = schwab_instance.option_chain('ACME',
                                          contract_type: 'CALL',
                                          strike_range: 'OTM')

      # Both should be option chains but they should be separate instances
      expect(chain1).to be_an_instance_of(Platypi::Schwab::DataObjects::OptionChain)
      expect(chain2).to be_an_instance_of(Platypi::Schwab::DataObjects::OptionChain)
    end
  end

  describe '#account' do
    let(:account_response) do
      instance_double('Response',
                      body: File.read('spec/fixtures/account.json'))
    end

    it 'fetches and returns account information' do
      expect(mock_client).to receive(:get_account)
        .with('ABC123XYZ', fields: nil)
        .and_return(account_response)

      account = schwab_instance.account
      expect(account).to be_an_instance_of(Platypi::Schwab::DataObjects::Account)
      expect(account.account_number).to eq('11111111')
    end

    it 'accepts optional fields parameter' do
      expect(mock_client).to receive(:get_account)
        .with('ABC123XYZ', fields: 'positions,orders')
        .and_return(account_response)

      account = schwab_instance.account(fields: 'positions,orders')
      expect(account).to be_an_instance_of(Platypi::Schwab::DataObjects::Account)
    end
  end

  describe '#transactions' do
    let(:transactions_response) do
      instance_double('Response',
                      body: File.read('spec/fixtures/transactions.json'))
    end

    it 'fetches and returns transactions' do
      # Allow specific method call with empty hash
      expect(mock_client).to receive(:get_transactions)
        .with('ABC123XYZ')
        .and_return(transactions_response)

      transactions = schwab_instance.transactions
      expect(transactions).to be_an_instance_of(Array)
      expect(transactions.size).to eq(2)
      expect(transactions.first).to be_an_instance_of(Platypi::Schwab::DataObjects::Transaction)
      expect(transactions.first.type).to eq('TRADE')
      expect(transactions.first.order_id).to eq('1002613435352')

      # Verify the transfer items
      expect(transactions.first.transfer_items).to be_an_instance_of(Array)
      expect(transactions.first.transfer_items.first.instrument.symbol).to eq('MRVL  250321C00155000')
    end

    it 'accepts optional parameters' do
      from_date = Date.new(2025, 1, 1)
      to_date = Date.new(2025, 1, 31)

      expect(mock_client).to receive(:get_transactions)
        .with('ABC123XYZ', {
                start_date: from_date,
                end_date: to_date,
                transaction_types: 'TRADE',
                symbol: 'MRVL'
              })
        .and_return(transactions_response)

      transactions = schwab_instance.transactions(
        from_date: from_date,
        to_date: to_date,
        transaction_types: 'TRADE',
        symbol: 'MRVL'
      )

      expect(transactions).to be_an_instance_of(Array)
      expect(transactions.first).to be_an_instance_of(Platypi::Schwab::DataObjects::Transaction)

      # Verify that transfer items are processed correctly
      expect(transactions.first.transfer_items.size).to be > 0

      # Check if fees are extracted correctly
      fee_items = transactions.first.transfer_items.select(&:fee_type)
      expect(fee_items).not_to be_empty
    end
  end

  describe '#account_orders' do
    let(:orders_response) do
      instance_double('Response',
                      body: File.read('spec/fixtures/orders.json'))
    end

    it 'fetches and returns orders for the account' do
      from_date = Date.new(2025, 1, 1)
      to_date = Date.new(2025, 1, 31)
      status = 'FILLED'

      expect(mock_client).to receive(:get_account_orders)
        .with('ABC123XYZ', from_entered_datetime: from_date, to_entered_datetime: to_date, status: status)
        .and_return(orders_response)

      orders = schwab_instance.account_orders(from_date: from_date, to_date: to_date, status: status)
      expect(orders).to be_an_instance_of(Array)
      expect(orders.first).to be_an_instance_of(Platypi::Schwab::DataObjects::Order)
      expect(orders.first.status).to eq('FILLED')
    end
  end

  describe '#preview_order' do
    let(:preview_response) do
      instance_double('Response',
                      body: File.read('spec/fixtures/order_preview.json'))
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
              symbol: 'SPX  250317P04350000'
            },
            instruction: 'SELL_TO_OPEN',
            quantity: 1
          },
          {
            instrument: {
              symbol: 'SPX  250317P04250000'
            },
            instruction: 'BUY_TO_OPEN',
            quantity: 1
          }
        ]
      }

      expect(mock_client).to receive(:preview_order)
        .with('ABC123XYZ', order_data)
        .and_return(preview_response)

      preview = schwab_instance.preview_order(order_data)
      expect(preview).to be_an_instance_of(Platypi::Schwab::DataObjects::OrderPreview)
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
      order_id = '1002613435352'

      expect(mock_client).to receive(:get_order)
        .with(order_id, 'ABC123XYZ')
        .and_return(order_response)

      order = schwab_instance.get_order(order_id)
      expect(order).to be_an_instance_of(Platypi::Schwab::DataObjects::Order)
      expect(order.order_id.to_s).to eq('1002613435352')
    end
  end

  describe '#cancel_order' do
    let(:cancel_response) do
      instance_double('Response', status: 200)
    end

    it 'cancels an order and returns success status' do
      order_id = 1_002_613_435_352

      expect(mock_client).to receive(:cancel_order)
        .with(order_id, 'ABC123XYZ')
        .and_return(cancel_response)

      result = schwab_instance.cancel_order(order_id)
      expect(result).to be true
    end
  end
end
